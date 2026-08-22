import Foundation

actor PDFDocumentStructure<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let revisions: [PDFDocumentRevision]
  private let headerVersion: PDFFileVersion
  private let limits: PDFParsingLimits
  private var catalogs = [PDFRevisionIdentifier: PDFDocumentCatalog]()
  private var validatedPageCounts = [PDFRevisionIdentifier: Int]()
  private var pendingPageValidations = [PDFRevisionIdentifier: Task<Int, Error>]()
  private var pageLabelRangeCache = [PDFRevisionIdentifier: [PDFPageLabelRange]?]()
  private var optionalContentCache = [PDFRevisionIdentifier: PDFOptionalContentProperties?]()
  private var structureTreeCache = [PDFRevisionIdentifier: PDFStructureTree?]()
  private var structureElementCache = [PDFRevisionIdentifier: [PDFStructureElementIdentifier: PDFStructureElement]]()
  private var validatedStructureTrees = Set<PDFRevisionIdentifier>()
  private var closed = false

  init(
    resolver: PDFDocumentResolver<Session>,
    revisions: [PDFDocumentRevision],
    headerVersion: PDFFileVersion,
    limits: PDFParsingLimits
  ) {
    self.resolver = resolver
    self.revisions = revisions
    self.headerVersion = headerVersion
    self.limits = limits
  }

  func catalog(in revision: PDFRevisionIdentifier) async throws -> PDFDocumentCatalog {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard let revisionValue = revisions.first(where: { $0.identifier == revision }) else {
      throw PDFParsingError.unknownRevision(revision)
    }
    if let cached = catalogs[revision] { return cached }
    let object = try await resolver.resolve(revisionValue.root, in: revision)
    guard case .value(.dictionary(let dictionary)) = object.value,
      dictionary.pdfName(named: "Type") == PDFName("Catalog"),
      let pagesReference = dictionary.pdfReference(named: "Pages")
    else {
      throw malformed("The document root must be an ordinary Catalog with an indirect Pages root.")
    }
    let pagesObject = try await resolver.resolve(pagesReference, in: revision)
    guard case .value(.dictionary(let pages)) = pagesObject.value,
      pages.pdfName(named: "Type") == PDFName("Pages"),
      let kids = pages.pdfArray(named: "Kids"),
      kids.allSatisfy({ if case .reference = $0 { true } else { false } }),
      let count = pages.pdfInteger(named: "Count"),
      count >= 0,
      count <= Int64(limits.maximumPages)
    else {
      throw malformed("The page-tree root is malformed.")
    }
    let effectiveVersion = try effectiveVersion(from: dictionary)
    let catalog = PDFDocumentCatalog(
      reference: revisionValue.root,
      rawDictionary: dictionary,
      definingRevision: object.definitionRevision ?? revision,
      pageTreeRoot: pagesReference,
      declaredPageCount: Int(count),
      effectiveVersion: effectiveVersion
    )
    catalogs[revision] = catalog
    return catalog
  }

  func close() {
    closed = true
    for task in pendingPageValidations.values { task.cancel() }
    pendingPageValidations.removeAll()
    catalogs.removeAll()
    validatedPageCounts.removeAll()
    pageLabelRangeCache.removeAll()
    optionalContentCache.removeAll()
    structureTreeCache.removeAll()
    structureElementCache.removeAll()
    validatedStructureTrees.removeAll()
  }

  func pageCount(in revision: PDFRevisionIdentifier) async throws -> Int {
    if let count = validatedPageCounts[revision] { return count }
    if let task = pendingPageValidations[revision] { return try await task.value }
    let task = Task<Int, Error> { try await self.auditPageTree(in: revision) }
    pendingPageValidations[revision] = task
    do {
      let count = try await task.value
      pendingPageValidations[revision] = nil
      validatedPageCounts[revision] = count
      return count
    } catch {
      pendingPageValidations[revision] = nil
      throw error
    }
  }

  func validatePageTree(in revision: PDFRevisionIdentifier) async throws {
    _ = try await pageCount(in: revision)
  }

  func page(at index: Int, in revision: PDFRevisionIdentifier) async throws -> PDFPage {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard index >= 0 else { throw PDFParsingError.pageIndexOutOfRange(index) }
    let catalog = try await catalog(in: revision)
    guard index < catalog.declaredPageCount else {
      throw PDFParsingError.pageIndexOutOfRange(index)
    }
    let state = PageWalkState(target: index)
    let inherited = InheritedPageAttributes()
    _ = try await walk(
      catalog.pageTreeRoot,
      expectedParent: nil,
      ancestors: [],
      inherited: inherited,
      revision: revision,
      state: state,
      auditCompletely: false
    )
    guard let page = state.found else {
      throw malformed("The page-tree Count does not identify the requested page.")
    }
    return page
  }

  func pages(in revision: PDFRevisionIdentifier) async throws -> PDFPageSequence {
    let catalog = try await catalog(in: revision)
    let state = PDFPageSequenceState(
      declaredCount: catalog.declaredPageCount,
      pageAt: { [weak self] index in
        guard let self else { throw PDFParsingError.documentClosed }
        return try await self.page(at: index, in: revision)
      },
      validate: { [weak self] in
        guard let self else { throw PDFParsingError.documentClosed }
        return try await self.pageCount(in: revision)
      }
    )
    return PDFPageSequence(state: state)
  }

  func pageLabelRanges(in revision: PDFRevisionIdentifier) async throws -> [PDFPageLabelRange]? {
    if let cached = pageLabelRangeCache[revision] { return cached }
    let catalog = try await catalog(in: revision)
    guard let root = catalog.rawDictionary["PageLabels"] else {
      pageLabelRangeCache[revision] = .some(nil)
      return nil
    }
    let entries = try await PDFCollectionTreeReader(
      kind: .number,
      limits: limits,
      resolve: { [resolver] reference in try await resolver.resolve(reference, in: revision) }
    ).read(root)
    guard !entries.isEmpty, entries.first?.key == .number(0) else {
      throw malformed("A PageLabels number tree must begin at page index zero.")
    }
    var ranges = [PDFPageLabelRange]()
    for entry in entries {
      guard case .number(let rawIndex) = entry.key,
        rawIndex >= 0,
        rawIndex < Int64(catalog.declaredPageCount)
      else { throw malformed("A page-label range index is outside the page tree.") }
      let value = try await resolveDirect(entry.value, in: revision, visited: [])
      guard case .dictionary(let dictionary) = value else {
        throw malformed("A page-label range value must be a dictionary.")
      }
      let prefix: String
      if let prefixValue = dictionary["P"] {
        guard case .string(let string) = prefixValue else {
          throw malformed("A page-label prefix must be a text string.")
        }
        prefix = try PDFTextStringDecoder.decode(
          string,
          allowsUTF8: catalog.effectiveVersion == .v2_0
        )
      } else {
        prefix = ""
      }
      let style = try pageLabelStyle(dictionary["S"])
      let start = dictionary.pdfInteger(named: "St") ?? 1
      guard start >= 1, start <= Int64(Int.max) else {
        throw malformed("A page-label starting number must be at least one.")
      }
      let range = PDFPageLabelRange(
        startPageIndex: Int(rawIndex),
        prefix: prefix,
        style: style,
        startNumber: Int(start)
      )
      _ = try renderedLabel(range: range, pageIndex: Int(rawIndex))
      ranges.append(range)
    }
    pageLabelRangeCache[revision] = ranges
    return ranges
  }

  func optionalContentProperties(
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFOptionalContentProperties? {
    if let cached = optionalContentCache[revision] { return cached }
    let catalog = try await catalog(in: revision)
    guard let rawProperties = catalog.rawDictionary["OCProperties"] else {
      optionalContentCache[revision] = .some(nil)
      return nil
    }
    let propertiesObject = try await resolveDirect(rawProperties, in: revision, visited: [])
    guard case .dictionary(let dictionary) = propertiesObject,
      let groupObjects = dictionary.pdfArray(named: "OCGs"),
      groupObjects.count <= limits.maximumOptionalContentGroups,
      let defaultObject = dictionary["D"]
    else { throw malformed("OCProperties must contain bounded OCGs and a default configuration.") }

    var groups = [PDFOptionalContentGroup]()
    var groupIDs = Set<PDFOptionalContentGroupIdentifier>()
    for object in groupObjects {
      guard case .reference(let reference) = object else {
        throw malformed("Each OCG must be an indirect object.")
      }
      let identifier = PDFOptionalContentGroupIdentifier(reference: reference)
      guard groupIDs.insert(identifier).inserted else {
        throw malformed("The OCG array contains a duplicate group.")
      }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let group)) = resolved.value,
        group.pdfName(named: "Type") == PDFName("OCG"),
        case .string(let rawName)? = group["Name"]
      else { throw malformed("An OCG is not a valid indirect OCG dictionary.") }
      let name = try PDFTextStringDecoder.decode(
        rawName,
        allowsUTF8: catalog.effectiveVersion == .v2_0
      )
      let intents = try optionalContentIntents(group["Intent"])
      groups.append(.init(identifier: identifier, name: name, intents: intents, rawDictionary: group))
    }

    let defaultDictionary = try await optionalContentDictionary(defaultObject, in: revision)
    let defaultConfiguration = try optionalContentConfiguration(
      defaultDictionary,
      identifier: .defaultConfiguration,
      knownGroups: groupIDs,
      allowsUTF8: catalog.effectiveVersion == .v2_0
    )
    var alternates = [PDFOptionalContentConfiguration]()
    if let rawAlternates = dictionary["Configs"] {
      let resolved = try await resolveDirect(rawAlternates, in: revision, visited: [])
      guard case .array(let values) = resolved,
        values.count <= limits.maximumOptionalContentGroups
      else { throw malformed("Configs must be a bounded array.") }
      for (index, value) in values.enumerated() {
        let config = try await optionalContentDictionary(value, in: revision)
        alternates.append(try optionalContentConfiguration(
          config,
          identifier: .alternate(index),
          knownGroups: groupIDs,
          allowsUTF8: catalog.effectiveVersion == .v2_0
        ))
      }
    }
    let result = PDFOptionalContentProperties(
      groups: groups,
      defaultConfiguration: defaultConfiguration,
      alternateConfigurations: alternates
    )
    optionalContentCache[revision] = result
    return result
  }

  func optionalContentVisibility(
    of object: PDFObject,
    selection: PDFOptionalContentSelection,
    context: PDFOptionalContentContext,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFOptionalContentVisibility {
    guard let properties = try await optionalContentProperties(in: revision) else {
      throw malformed("Optional content cannot be evaluated without OCProperties.")
    }
    let configuration = try selectedConfiguration(selection, properties: properties)
    var states = optionalContentStates(configuration, groups: properties.groups)
    if case .custom(_, let overrides) = selection {
      for (group, state) in overrides where states[group] != nil { states[group] = state }
    }
    try applyUsageApplications(
      configuration.rawDictionary["AS"],
      context: context,
      groups: properties.groups,
      states: &states
    )
    var controlling = Set<PDFOptionalContentGroupIdentifier>()
    let visible = try await evaluateOptionalContent(
      object,
      revision: revision,
      states: states,
      groups: Set(properties.groups.map(\.identifier)),
      controlling: &controlling,
      depth: 0
    )
    return .init(isVisible: visible, controllingGroups: controlling.sorted())
  }

  func structureTree(in revision: PDFRevisionIdentifier) async throws -> PDFStructureTree? {
    if let cached = structureTreeCache[revision] { return cached }
    let catalog = try await catalog(in: revision)
    guard let rawRoot = catalog.rawDictionary["StructTreeRoot"] else {
      structureTreeCache[revision] = .some(nil)
      return nil
    }
    guard case .reference(let reference) = rawRoot else {
      throw malformed("StructTreeRoot must be an indirect object.")
    }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = resolved.value,
      dictionary.pdfName(named: "Type") == PDFName("StructTreeRoot")
    else { throw malformed("StructTreeRoot is not a valid structure-tree root.") }
    let children = try await structureChildren(
      dictionary["K"], parent: reference, inheritedPage: nil, revision: revision, depth: 0
    )
    guard children.allSatisfy({ if case .element = $0 { true } else { false } }) else {
      throw malformed("StructTreeRoot children must be structure elements.")
    }
    let roleMap = try structureRoleMap(dictionary["RoleMap"])
    try validateRoleMap(roleMap)
    let classMap = try structureClassMap(dictionary["ClassMap"])
    let namespaces = try await structureNamespaces(dictionary["Namespaces"], revision: revision)
    let nextKey: Int?
    if let value = dictionary["ParentTreeNextKey"] {
      let raw = try structureInteger(value)
      guard raw >= 0 else { throw malformed("ParentTreeNextKey must be nonnegative.") }
      nextKey = raw
    } else { nextKey = nil }
    let tree = PDFStructureTree(
      reference: reference,
      children: children,
      roleMap: roleMap,
      classMap: classMap,
      namespaces: namespaces,
      parentTreeNextKey: nextKey,
      rawDictionary: dictionary,
      definingRevision: resolved.definitionRevision ?? revision
    )
    structureTreeCache[revision] = tree
    return tree
  }

  func structureElement(
    _ identifier: PDFStructureElementIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFStructureElement {
    if let cached = structureElementCache[revision]?[identifier] { return cached }
    guard try await structureTree(in: revision) != nil else {
      throw malformed("The document has no logical structure tree.")
    }
    let resolved = try await resolver.resolve(identifier.reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = resolved.value,
      dictionary.pdfName(named: "Type") == PDFName("StructElem"),
      let structureType = dictionary.pdfName(named: "S"),
      let parent = dictionary.pdfReference(named: "P")
    else { throw malformed("A structure element dictionary is malformed.") }
    let page = dictionary.pdfReference(named: "Pg")
    let children = try await structureChildren(
      dictionary["K"], parent: identifier.reference, inheritedPage: page,
      revision: revision, depth: 0
    )
    let catalog = try await catalog(in: revision)
    let element = PDFStructureElement(
      identifier: identifier,
      structureType: structureType,
      namespace: dictionary.pdfReference(named: "NS"),
      parent: parent,
      page: page,
      children: children,
      identifierBytes: structureStringBytes(dictionary["ID"]),
      title: try structureText(dictionary["T"], allowsUTF8: catalog.effectiveVersion == .v2_0),
      language: try structureText(dictionary["Lang"], allowsUTF8: catalog.effectiveVersion == .v2_0),
      alternateDescription: try structureText(dictionary["Alt"], allowsUTF8: catalog.effectiveVersion == .v2_0),
      replacementText: try structureText(dictionary["ActualText"], allowsUTF8: catalog.effectiveVersion == .v2_0),
      expansion: try structureText(dictionary["E"], allowsUTF8: catalog.effectiveVersion == .v2_0),
      classNames: try structureClassNames(dictionary["C"]),
      attributes: try structureAttributes(dictionary["A"]),
      rawDictionary: dictionary,
      definingRevision: resolved.definitionRevision ?? revision
    )
    structureElementCache[revision, default: [:]][identifier] = element
    return element
  }

  func validateStructureTree(in revision: PDFRevisionIdentifier) async throws {
    if validatedStructureTrees.contains(revision) { return }
    guard let tree = try await structureTree(in: revision) else { return }
    var visited = Set<PDFStructureElementIdentifier>()
    var active = Set<PDFStructureElementIdentifier>()
    var scratch = 0
    for child in tree.children {
      guard case .element(let identifier) = child else { continue }
      try await auditStructureElement(
        identifier, expectedParent: tree.reference, revision: revision,
        visited: &visited, active: &active, scratch: &scratch, depth: 0
      )
    }
    try await validateStructureParentTree(tree, revision: revision, elements: visited)
    try await validateStructureIDTree(tree, revision: revision, elements: visited)
    validatedStructureTrees.insert(revision)
  }

  private final class PageWalkState {
    let target: Int?
    var index = 0
    var found: PDFPage?
    var visited = Set<PDFObjectReference>()
    var scratch = 0

    init(target: Int? = nil) { self.target = target }
  }

  private struct InheritedValue {
    let object: PDFObject
    let origin: PDFPageAttributeOrigin
  }

  private struct InheritedPageAttributes {
    var resources: InheritedValue?
    var mediaBox: InheritedValue?
    var cropBox: InheritedValue?
    var rotate: InheritedValue?

    func applying(_ dictionary: [PDFName: PDFObject], at reference: PDFObjectReference) -> Self {
      var result = self
      let origin = PDFPageAttributeOrigin.ancestor(reference)
      if let value = dictionary["Resources"] { result.resources = .init(object: value, origin: origin) }
      if let value = dictionary["MediaBox"] { result.mediaBox = .init(object: value, origin: origin) }
      if let value = dictionary["CropBox"] { result.cropBox = .init(object: value, origin: origin) }
      if let value = dictionary["Rotate"] { result.rotate = .init(object: value, origin: origin) }
      return result
    }
  }

  private func auditPageTree(in revision: PDFRevisionIdentifier) async throws -> Int {
    guard !closed else { throw PDFParsingError.documentClosed }
    let catalog = try await catalog(in: revision)
    let state = PageWalkState()
    let count = try await walk(
      catalog.pageTreeRoot,
      expectedParent: nil,
      ancestors: [],
      inherited: InheritedPageAttributes(),
      revision: revision,
      state: state,
      auditCompletely: true
    )
    guard count == catalog.declaredPageCount else {
      throw malformed("The page-tree root Count does not equal its leaf page count.")
    }
    return count
  }

  private func walk(
    _ reference: PDFObjectReference,
    expectedParent: PDFObjectReference?,
    ancestors: [PDFObjectReference],
    inherited: InheritedPageAttributes,
    revision: PDFRevisionIdentifier,
    state: PageWalkState,
    auditCompletely: Bool
  ) async throws -> Int {
    try Task.checkCancellation()
    guard state.visited.insert(reference).inserted else {
      throw malformed("The page tree contains a cycle or duplicate node.")
    }
    state.scratch = try addScratch(state.scratch, 128 + ancestors.count * 16)
    let object = try await resolver.resolve(reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = object.value,
      let type = dictionary.pdfName(named: "Type")
    else {
      throw malformed("A page-tree child must be an ordinary typed dictionary.")
    }
    if let expectedParent {
      guard dictionary.pdfReference(named: "Parent") == expectedParent else {
        throw malformed("A page-tree child has an incorrect Parent.")
      }
    } else if dictionary["Parent"] != nil {
      throw malformed("The page-tree root must not have a Parent.")
    }

    if type == PDFName("Page") {
      guard expectedParent != nil else { throw malformed("The page-tree root cannot be a Page.") }
      let pageIndex = state.index
      state.index += 1
      if state.target == pageIndex {
        state.found = try await makePage(
          index: pageIndex,
          reference: reference,
          object: object,
          dictionary: dictionary,
          ancestors: ancestors,
          inherited: inherited,
          revision: revision
        )
      }
      return 1
    }

    guard type == PDFName("Pages"),
      let kids = dictionary.pdfArray(named: "Kids"),
      let declaredCount = dictionary.pdfInteger(named: "Count"),
      declaredCount >= 0,
      declaredCount <= Int64(limits.maximumPages)
    else {
      throw malformed("A page-tree node is malformed.")
    }
    let nextInherited = inherited.applying(dictionary, at: reference)
    let nextAncestors = ancestors + [reference]
    var count = 0
    for kid in kids {
      guard case .reference(let childReference) = kid else {
        throw malformed("Page-tree Kids must contain indirect references.")
      }
      let childCount = try await walk(
        childReference,
        expectedParent: reference,
        ancestors: nextAncestors,
        inherited: nextInherited,
        revision: revision,
        state: state,
        auditCompletely: auditCompletely
      )
      count = try addPages(count, childCount)
      if !auditCompletely, state.found != nil { return count }
    }
    guard count == Int(declaredCount) else {
      throw malformed("A page-tree node Count does not equal its leaf page count.")
    }
    return count
  }

  private func makePage(
    index: Int,
    reference: PDFObjectReference,
    object: PDFIndirectObject,
    dictionary: [PDFName: PDFObject],
    ancestors: [PDFObjectReference],
    inherited: InheritedPageAttributes,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFPage {
    let pageOrigin = PDFPageAttributeOrigin.page(reference)
    let resourcesValue = dictionary["Resources"].map { InheritedValue(object: $0, origin: pageOrigin) }
      ?? inherited.resources
    let mediaValue = dictionary["MediaBox"].map { InheritedValue(object: $0, origin: pageOrigin) }
      ?? inherited.mediaBox
    guard let resourcesValue, let mediaValue else {
      throw malformed("A page requires effective Resources and MediaBox values.")
    }
    let resources = try await resolveDictionary(resourcesValue, in: revision)
    let media = try await resolveRectangle(mediaValue, in: revision)
    let cropValue = dictionary["CropBox"].map { InheritedValue(object: $0, origin: pageOrigin) }
      ?? inherited.cropBox
    let crop: PDFPageAttribute<PDFRectangle>
    if let cropValue {
      crop = try await resolveRectangle(cropValue, in: revision)
    } else {
      crop = PDFPageAttribute(value: media.value, origin: .defaulted)
    }
    let bleed = try await noninheritedRectangle(
      named: "BleedBox",
      dictionary: dictionary,
      reference: reference,
      defaultValue: crop.value,
      revision: revision
    )
    let trim = try await noninheritedRectangle(
      named: "TrimBox",
      dictionary: dictionary,
      reference: reference,
      defaultValue: crop.value,
      revision: revision
    )
    let art = try await noninheritedRectangle(
      named: "ArtBox",
      dictionary: dictionary,
      reference: reference,
      defaultValue: crop.value,
      revision: revision
    )
    let rotateValue = dictionary["Rotate"].map { InheritedValue(object: $0, origin: pageOrigin) }
      ?? inherited.rotate
    let rotation = try await resolveRotation(rotateValue, in: revision)
    let userUnit = try await resolveUserUnit(dictionary["UserUnit"], page: reference, in: revision)
    let mediaBoundary = PDFPageBoundary(declared: media, effective: media.value)
    let cropBoundary = PDFPageBoundary(
      declared: crop,
      effective: crop.value.intersection(with: media.value)
    )
    let geometry = PDFPageGeometry(
      mediaBox: mediaBoundary,
      cropBox: cropBoundary,
      bleedBox: .init(declared: bleed, effective: bleed.value.intersection(with: media.value)),
      trimBox: .init(declared: trim, effective: trim.value.intersection(with: media.value)),
      artBox: .init(declared: art, effective: art.value.intersection(with: media.value)),
      rotation: rotation,
      userUnit: userUnit
    )
    let contents = try await resolveContents(dictionary["Contents"], in: revision)
    let label = try await pageLabel(for: index, in: revision)
    return PDFPage(
      index: index,
      reference: reference,
      rawDictionary: dictionary,
      definingRevision: object.definitionRevision ?? revision,
      ancestorReferences: ancestors,
      resources: resources,
      geometry: geometry,
      contentStreams: contents,
      label: label
    )
  }

  private func resolveContents(
    _ value: PDFObject?,
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFStreamObject] {
    guard let value else { return [] }
    let references: [PDFObjectReference]
    switch value {
    case .reference(let reference):
      references = [reference]
    case .array(let values):
      guard !values.isEmpty else { throw malformed("A Contents array cannot be empty.") }
      references = try values.map {
        guard case .reference(let reference) = $0 else {
          throw malformed("Contents arrays must contain indirect stream references.")
        }
        return reference
      }
    default:
      throw malformed("Contents must be an indirect stream or an array of indirect streams.")
    }
    guard references.count <= limits.maximumPageContentStreams else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "A page contains too many content streams.")
      )
    }
    var streams = [PDFStreamObject]()
    streams.reserveCapacity(references.count)
    for reference in references {
      let object = try await resolver.resolve(reference, in: revision)
      guard case .stream(let stream) = object.value, stream.revision == revision else {
        throw malformed("A Contents reference must resolve to a stream in the selected revision.")
      }
      streams.append(stream)
    }
    return streams
  }

  private func pageLabel(
    for pageIndex: Int,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPageLabel? {
    guard let ranges = try await pageLabelRanges(in: revision),
      let range = ranges.last(where: { $0.startPageIndex <= pageIndex })
    else { return nil }
    return PDFPageLabel(
      pageIndex: pageIndex,
      text: try renderedLabel(range: range, pageIndex: pageIndex),
      range: range
    )
  }

  private func pageLabelStyle(_ object: PDFObject?) throws -> PDFPageLabelStyle {
    guard let object else { return .none }
    guard case .name(let name) = object else {
      throw malformed("A page-label style must be a name.")
    }
    return switch name {
    case PDFName("D"): .decimal
    case PDFName("R"): .uppercaseRoman
    case PDFName("r"): .lowercaseRoman
    case PDFName("A"): .uppercaseLetters
    case PDFName("a"): .lowercaseLetters
    default: throw malformed("A page-label style is unsupported.")
    }
  }

  private func renderedLabel(range: PDFPageLabelRange, pageIndex: Int) throws -> String {
    let offset = pageIndex - range.startPageIndex
    let (number, overflow) = range.startNumber.addingReportingOverflow(offset)
    guard !overflow, number > 0 else { throw malformed("A page-label number overflows.") }
    if range.style == .uppercaseRoman || range.style == .lowercaseRoman {
      guard number <= limits.maximumGeneratedPageLabelBytes * 1_000 else {
        throw PDFParsingError.limitExceeded(
          .init(offset: 0, message: "Generated Roman page-label text exceeds its limit.")
        )
      }
    }
    if range.style == .uppercaseLetters || range.style == .lowercaseLetters {
      guard (number - 1) / 26 + 1 <= limits.maximumGeneratedPageLabelBytes else {
        throw PDFParsingError.limitExceeded(
          .init(offset: 0, message: "Generated letter page-label text exceeds its limit.")
        )
      }
    }
    let suffix: String
    switch range.style {
    case .none: suffix = ""
    case .decimal: suffix = String(number)
    case .uppercaseRoman: suffix = roman(number)
    case .lowercaseRoman: suffix = roman(number).lowercased()
    case .uppercaseLetters: suffix = repeatedLetter(number, uppercase: true)
    case .lowercaseLetters: suffix = repeatedLetter(number, uppercase: false)
    }
    let value = range.prefix + suffix
    guard value.utf8.count <= limits.maximumGeneratedPageLabelBytes else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "Generated page-label text exceeds its limit.")
      )
    }
    return value
  }

  private func roman(_ number: Int) -> String {
    let values = [
      (1_000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
      (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
      (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]
    var remainder = number
    var result = ""
    for (value, symbol) in values {
      while remainder >= value {
        result += symbol
        remainder -= value
      }
    }
    return result
  }

  private func repeatedLetter(_ number: Int, uppercase: Bool) -> String {
    let index = (number - 1) % 26
    let count = (number - 1) / 26 + 1
    let base = uppercase ? 65 : 97
    return String(repeating: String(UnicodeScalar(base + index)!), count: count)
  }

  private func resolveDictionary(
    _ value: InheritedValue,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPageAttribute<[PDFName: PDFObject]> {
    let object = try await resolveDirect(value.object, in: revision, visited: [])
    guard case .dictionary(let dictionary) = object else {
      throw malformed("An effective Resources value must be a dictionary.")
    }
    return .init(value: dictionary, origin: value.origin)
  }

  private func resolveRectangle(
    _ value: InheritedValue,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPageAttribute<PDFRectangle> {
    let object = try await resolveDirect(value.object, in: revision, visited: [])
    guard case .array(let values) = object, values.count == 4 else {
      throw malformed("A page boundary must be a four-number array.")
    }
    let numbers = try values.map { object -> Double in
      guard case .number(let number) = object else {
        throw malformed("A page boundary contains a nonnumeric coordinate.")
      }
      return doubleValue(number)
    }
    guard let rectangle = try? PDFRectangle(
      x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]
    ) else {
      throw malformed("A page boundary contains a nonfinite coordinate.")
    }
    return .init(value: rectangle, origin: value.origin)
  }

  private func noninheritedRectangle(
    named name: PDFName,
    dictionary: [PDFName: PDFObject],
    reference: PDFObjectReference,
    defaultValue: PDFRectangle,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFPageAttribute<PDFRectangle> {
    guard let object = dictionary[name] else {
      return .init(value: defaultValue, origin: .defaulted)
    }
    return try await resolveRectangle(
      .init(object: object, origin: .page(reference)),
      in: revision
    )
  }

  private func resolveRotation(
    _ value: InheritedValue?,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPageAttribute<PDFPageRotation> {
    guard let value else { return .init(value: .degrees0, origin: .defaulted) }
    let object = try await resolveDirect(value.object, in: revision, visited: [])
    guard case .number(.integer(let raw)) = object, raw.isMultiple(of: 90) else {
      throw malformed("Rotate must be an integer divisible by 90.")
    }
    let normalized = Int((raw % 360 + 360) % 360)
    guard let rotation = PDFPageRotation(rawValue: normalized) else {
      throw malformed("Rotate cannot be normalized.")
    }
    return .init(value: rotation, origin: value.origin)
  }

  private func resolveUserUnit(
    _ value: PDFObject?,
    page: PDFObjectReference,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPageAttribute<Double> {
    guard let value else { return .init(value: 1, origin: .defaulted) }
    let object = try await resolveDirect(value, in: revision, visited: [])
    guard case .number(let number) = object else {
      throw malformed("UserUnit must be a finite positive number.")
    }
    let numericValue = doubleValue(number)
    guard numericValue.isFinite, numericValue > 0
    else {
      throw malformed("UserUnit must be a finite positive number.")
    }
    return .init(value: numericValue, origin: .page(page))
  }

  private func doubleValue(_ number: PDFNumber) -> Double {
    switch number {
    case .integer(let value): Double(value)
    case .real(let value): value
    }
  }

  private func resolveDirect(
    _ object: PDFObject,
    in revision: PDFRevisionIdentifier,
    visited: Set<PDFObjectReference>
  ) async throws -> PDFObject {
    guard case .reference(let reference) = object else { return object }
    guard !visited.contains(reference) else {
      throw PDFParsingError.referenceCycle(Array(visited) + [reference])
    }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .value(let value) = resolved.value else {
      throw malformed("A page attribute reference resolves to a stream.")
    }
    return try await resolveDirect(value, in: revision, visited: visited.union([reference]))
  }

  private func addPages(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, result <= limits.maximumPages else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The page tree exceeds its page limit.")
      )
    }
    return result
  }

  private func addScratch(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, result <= limits.maximumPageTreeScratchBytes else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "Page-tree validation exceeds its storage limit.")
      )
    }
    return result
  }

  private func effectiveVersion(from catalog: [PDFName: PDFObject]) throws -> PDFFileVersion {
    guard let value = catalog["Version"] else { return headerVersion }
    guard case .name(let name) = value,
      let text = String(data: name.bytes, encoding: .ascii),
      let catalogVersion = PDFFileVersion(rawValue: text)
    else {
      throw malformed("Catalog Version must name a supported PDF version.")
    }
    let versions = PDFFileVersion.allCases
    guard let headerIndex = versions.firstIndex(of: headerVersion),
      let catalogIndex = versions.firstIndex(of: catalogVersion)
    else {
      throw malformed("The document version is unsupported.")
    }
    return versions[max(headerIndex, catalogIndex)]
  }

  private func optionalContentDictionary(
    _ object: PDFObject,
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFName: PDFObject] {
    let resolved = try await resolveDirect(object, in: revision, visited: [])
    guard case .dictionary(let dictionary) = resolved else {
      throw malformed("An optional-content configuration must be a dictionary.")
    }
    return dictionary
  }

  private func structureChildren(
    _ object: PDFObject?,
    parent: PDFObjectReference,
    inheritedPage: PDFObjectReference?,
    revision: PDFRevisionIdentifier,
    depth: Int
  ) async throws -> [PDFStructureChild] {
    guard let object else { return [] }
    guard depth <= limits.maximumStructureDepth else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Structure-tree depth exceeds its limit."))
    }
    if case .array(let values) = object {
      guard values.count <= limits.maximumStructureChildren else {
        throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Structure-element children exceed their limit."))
      }
      var result = [PDFStructureChild]()
      for value in values {
        result.append(contentsOf: try await structureChildren(
          value, parent: parent, inheritedPage: inheritedPage,
          revision: revision, depth: depth + 1
        ))
      }
      return result
    }
    if case .number(.integer(let rawMCID)) = object {
      guard rawMCID >= 0, rawMCID <= Int64(Int.max) else {
        throw malformed("A structure MCID must be nonnegative.")
      }
      return [.markedContent(.init(
        markedContentIdentifier: Int(rawMCID), page: inheritedPage, stream: nil
      ))]
    }
    let dictionary: [PDFName: PDFObject]
    let reference: PDFObjectReference?
    if case .reference(let value) = object {
      reference = value
      let resolved = try await resolver.resolve(value, in: revision)
      guard case .value(.dictionary(let value)) = resolved.value else {
        throw malformed("A structure kid reference must resolve to a dictionary.")
      }
      dictionary = value
    } else if case .dictionary(let value) = object {
      reference = nil
      dictionary = value
    } else {
      throw malformed("A structure kid has an invalid type.")
    }
    switch dictionary.pdfName(named: "Type") {
    case PDFName("StructElem"):
      guard let reference, dictionary.pdfReference(named: "P") == parent else {
        throw malformed("A structure element must be indirect and name its exact parent.")
      }
      return [.element(.init(reference: reference))]
    case PDFName("MCR"):
      guard let rawMCID = dictionary.pdfInteger(named: "MCID"), rawMCID >= 0,
        rawMCID <= Int64(Int.max)
      else { throw malformed("An MCR dictionary requires a nonnegative MCID.") }
      return [.markedContent(.init(
        markedContentIdentifier: Int(rawMCID),
        page: dictionary.pdfReference(named: "Pg") ?? inheritedPage,
        stream: dictionary.pdfReference(named: "Stm")
      ))]
    case PDFName("OBJR"):
      guard let object = dictionary.pdfReference(named: "Obj") else {
        throw malformed("An OBJR dictionary requires an indirect Obj.")
      }
      return [.object(.init(
        object: object,
        page: dictionary.pdfReference(named: "Pg") ?? inheritedPage
      ))]
    default:
      throw malformed("A structure kid dictionary has an invalid Type.")
    }
  }

  private func structureRoleMap(_ object: PDFObject?) throws -> [PDFName: PDFName] {
    guard let object else { return [:] }
    guard case .dictionary(let dictionary) = object else {
      throw malformed("RoleMap must be a dictionary.")
    }
    return try Dictionary(uniqueKeysWithValues: dictionary.map {
      guard case .name(let value) = $0.value else {
        throw malformed("RoleMap values must be names.")
      }
      return ($0.key, value)
    })
  }

  private func validateRoleMap(_ roleMap: [PDFName: PDFName]) throws {
    for start in roleMap.keys {
      var seen = Set<PDFName>()
      var current = start
      while let next = roleMap[current] {
        guard seen.insert(current).inserted else {
          throw malformed("RoleMap contains a cycle.")
        }
        current = next
      }
    }
  }

  private func structureClassMap(_ object: PDFObject?) throws -> [PDFName: [PDFObject]] {
    guard let object else { return [:] }
    guard case .dictionary(let dictionary) = object else {
      throw malformed("ClassMap must be a dictionary.")
    }
    return try Dictionary(uniqueKeysWithValues: dictionary.map { entry in
      switch entry.value {
      case .dictionary: return (entry.key, [entry.value])
      case .array(let values):
        guard values.allSatisfy({ if case .dictionary = $0 { true } else { false } }) else {
          throw malformed("ClassMap arrays must contain attribute dictionaries.")
        }
        return (entry.key, values)
      default: throw malformed("ClassMap values must be dictionaries or arrays.")
      }
    })
  }

  private func structureNamespaces(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> [PDFStructureNamespace] {
    guard let object else { return [] }
    guard case .array(let values) = object,
      values.count <= limits.maximumStructureChildren
    else { throw malformed("Namespaces must be a bounded array.") }
    let catalog = try await catalog(in: revision)
    guard catalog.effectiveVersion == .v2_0 else {
      throw malformed("Structure namespaces require PDF 2.0.")
    }
    var result = [PDFStructureNamespace]()
    var references = Set<PDFObjectReference>()
    for value in values {
      guard case .reference(let reference) = value,
        references.insert(reference).inserted
      else { throw malformed("Namespaces must contain unique indirect references.") }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let dictionary)) = resolved.value,
        dictionary.pdfName(named: "Type") == PDFName("Namespace"),
        case .string(let rawNamespace)? = dictionary["NS"]
      else { throw malformed("A structure namespace dictionary is malformed.") }
      result.append(.init(
        reference: reference,
        namespace: try PDFTextStringDecoder.decode(rawNamespace, allowsUTF8: true),
        schema: dictionary["Schema"],
        rawDictionary: dictionary
      ))
    }
    return result
  }

  private func structureInteger(_ object: PDFObject) throws -> Int {
    guard case .number(.integer(let value)) = object, let result = Int(exactly: value) else {
      throw malformed("A structure integer is invalid.")
    }
    return result
  }

  private func structureText(_ object: PDFObject?, allowsUTF8: Bool) throws -> String? {
    guard let object else { return nil }
    guard case .string(let value) = object else {
      throw malformed("A structure text value must be a string.")
    }
    return try PDFTextStringDecoder.decode(value, allowsUTF8: allowsUTF8)
  }

  private func structureStringBytes(_ object: PDFObject?) -> Data? {
    guard case .string(let value)? = object else { return nil }
    return value.bytes
  }

  private func structureClassNames(_ object: PDFObject?) throws -> [PDFName] {
    guard let object else { return [] }
    if case .name(let name) = object { return [name] }
    guard case .array(let values) = object else {
      throw malformed("A structure class entry must be a name or array.")
    }
    return try values.map {
      guard case .name(let name) = $0 else {
        throw malformed("A structure class array must contain names.")
      }
      return name
    }
  }

  private func structureAttributes(_ object: PDFObject?) throws -> [PDFObject] {
    guard let object else { return [] }
    if case .dictionary = object { return [object] }
    guard case .array(let values) = object else {
      throw malformed("A structure attribute entry must be a dictionary or array.")
    }
    var result = [PDFObject]()
    for value in values {
      if case .dictionary = value { result.append(value); continue }
      if case .number = value { continue }
      throw malformed("A structure attribute array is malformed.")
    }
    return result
  }

  private func auditStructureElement(
    _ identifier: PDFStructureElementIdentifier,
    expectedParent: PDFObjectReference,
    revision: PDFRevisionIdentifier,
    visited: inout Set<PDFStructureElementIdentifier>,
    active: inout Set<PDFStructureElementIdentifier>,
    scratch: inout Int,
    depth: Int
  ) async throws {
    guard depth <= limits.maximumStructureDepth else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Structure-tree depth exceeds its limit."))
    }
    guard !active.contains(identifier), visited.insert(identifier).inserted else {
      throw malformed("The structure tree contains a cycle or duplicate element.")
    }
    guard visited.count <= limits.maximumStructureElements else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Structure element count exceeds its limit."))
    }
    active.insert(identifier)
    scratch = try structureScratch(scratch, adding: 192)
    let element = try await structureElement(identifier, in: revision)
    guard element.parent == expectedParent else {
      throw malformed("A structure element has an incorrect parent.")
    }
    for child in element.children {
      if case .element(let childIdentifier) = child {
        try await auditStructureElement(
          childIdentifier, expectedParent: identifier.reference, revision: revision,
          visited: &visited, active: &active, scratch: &scratch, depth: depth + 1
        )
      }
    }
    active.remove(identifier)
  }

  private func validateStructureParentTree(
    _ tree: PDFStructureTree,
    revision: PDFRevisionIdentifier,
    elements: Set<PDFStructureElementIdentifier>
  ) async throws {
    guard let root = tree.rawDictionary["ParentTree"] else { return }
    let entries = try await PDFCollectionTreeReader(
      kind: .number, limits: limits,
      resolve: { [resolver] reference in try await resolver.resolve(reference, in: revision) }
    ).read(root)
    for entry in entries {
      guard case .number(let key) = entry.key, key >= 0 else {
        throw malformed("ParentTree keys must be nonnegative integers.")
      }
      let value = try await resolveDirect(entry.value, in: revision, visited: [])
      let values = if case .array(let array) = value { array } else { [value] }
      for item in values where item != .null {
        guard case .reference(let reference) = item,
          elements.contains(.init(reference: reference))
        else { throw malformed("ParentTree values must reference structure elements.") }
      }
    }
  }

  private func validateStructureIDTree(
    _ tree: PDFStructureTree,
    revision: PDFRevisionIdentifier,
    elements: Set<PDFStructureElementIdentifier>
  ) async throws {
    guard let root = tree.rawDictionary["IDTree"] else { return }
    let entries = try await PDFCollectionTreeReader(
      kind: .name, limits: limits,
      resolve: { [resolver] reference in try await resolver.resolve(reference, in: revision) }
    ).read(root)
    for entry in entries {
      guard case .name(let key) = entry.key,
        case .reference(let reference) = entry.value
      else { throw malformed("IDTree values must reference structure elements.") }
      let identifier = PDFStructureElementIdentifier(reference: reference)
      guard elements.contains(identifier),
        try await structureElement(identifier, in: revision).identifierBytes == key
      else { throw malformed("IDTree keys must equal their structure element IDs.") }
    }
  }

  private func structureScratch(_ value: Int, adding amount: Int) throws -> Int {
    let (result, overflow) = value.addingReportingOverflow(amount)
    guard !overflow, result <= limits.maximumStructureScratchBytes else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Structure-tree scratch exceeds its limit."))
    }
    return result
  }

  private func optionalContentIntents(_ object: PDFObject?) throws -> [PDFName] {
    guard let object else { return [PDFName("View")] }
    switch object {
    case .name(let name): return [name]
    case .array(let values):
      return try values.map {
        guard case .name(let name) = $0 else {
          throw malformed("Optional-content intents must be names.")
        }
        return name
      }
    default:
      throw malformed("Optional-content Intent must be a name or array of names.")
    }
  }

  private func optionalContentConfiguration(
    _ dictionary: [PDFName: PDFObject],
    identifier: PDFOptionalContentConfigurationIdentifier,
    knownGroups: Set<PDFOptionalContentGroupIdentifier>,
    allowsUTF8: Bool
  ) throws -> PDFOptionalContentConfiguration {
    let base: PDFOptionalContentBaseState
    switch dictionary.pdfName(named: "BaseState") ?? PDFName("ON") {
    case PDFName("ON"): base = .on
    case PDFName("OFF"): base = .off
    case PDFName("Unchanged"): base = .unchanged
    default: throw malformed("An optional-content BaseState is invalid.")
    }
    let on = try optionalContentGroupSet(dictionary["ON"], knownGroups: knownGroups)
    let off = try optionalContentGroupSet(dictionary["OFF"], knownGroups: knownGroups)
    guard on.isDisjoint(with: off) else {
      throw malformed("An optional-content group cannot be both ON and OFF.")
    }
    let locked = try optionalContentGroupSet(dictionary["Locked"], knownGroups: knownGroups)
    return .init(
      identifier: identifier,
      name: try optionalContentText(dictionary["Name"], allowsUTF8: allowsUTF8),
      creator: try optionalContentText(dictionary["Creator"], allowsUTF8: allowsUTF8),
      baseState: base,
      initiallyOn: on,
      initiallyOff: off,
      locked: locked,
      rawDictionary: dictionary
    )
  }

  private func optionalContentText(_ object: PDFObject?, allowsUTF8: Bool) throws -> String? {
    guard let object else { return nil }
    guard case .string(let value) = object else {
      throw malformed("Optional-content text values must be strings.")
    }
    return try PDFTextStringDecoder.decode(value, allowsUTF8: allowsUTF8)
  }

  private func optionalContentGroupSet(
    _ object: PDFObject?,
    knownGroups: Set<PDFOptionalContentGroupIdentifier>
  ) throws -> Set<PDFOptionalContentGroupIdentifier> {
    guard let object else { return [] }
    guard case .array(let values) = object else {
      throw malformed("An optional-content group list must be an array.")
    }
    var result = Set<PDFOptionalContentGroupIdentifier>()
    for value in values {
      guard case .reference(let reference) = value else {
        throw malformed("An optional-content group list must contain indirect references.")
      }
      let identifier = PDFOptionalContentGroupIdentifier(reference: reference)
      guard knownGroups.contains(identifier) else {
        throw malformed("An optional-content configuration references an unknown group.")
      }
      result.insert(identifier)
    }
    return result
  }

  private func selectedConfiguration(
    _ selection: PDFOptionalContentSelection,
    properties: PDFOptionalContentProperties
  ) throws -> PDFOptionalContentConfiguration {
    let identifier: PDFOptionalContentConfigurationIdentifier
    switch selection {
    case .documentDefault: identifier = .defaultConfiguration
    case .configuration(let value), .custom(let value, _): identifier = value
    }
    switch identifier {
    case .defaultConfiguration: return properties.defaultConfiguration
    case .alternate(let index):
      guard properties.alternateConfigurations.indices.contains(index) else {
        throw malformed("The selected optional-content configuration does not exist.")
      }
      return properties.alternateConfigurations[index]
    }
  }

  private func optionalContentStates(
    _ configuration: PDFOptionalContentConfiguration,
    groups: [PDFOptionalContentGroup]
  ) -> [PDFOptionalContentGroupIdentifier: PDFOptionalContentState] {
    var result: [PDFOptionalContentGroupIdentifier: PDFOptionalContentState] =
      Dictionary(uniqueKeysWithValues: groups.map {
        (
          $0.identifier,
          configuration.baseState == .off
            ? PDFOptionalContentState.off
            : PDFOptionalContentState.on
        )
      })
    for group in configuration.initiallyOn { result[group] = .on }
    for group in configuration.initiallyOff { result[group] = .off }
    return result
  }

  private func applyUsageApplications(
    _ object: PDFObject?,
    context: PDFOptionalContentContext,
    groups: [PDFOptionalContentGroup],
    states: inout [PDFOptionalContentGroupIdentifier: PDFOptionalContentState]
  ) throws {
    guard let object else { return }
    guard case .array(let applications) = object else {
      throw malformed("An optional-content AS entry must be an array.")
    }
    let event = switch context.purpose {
    case .view: PDFName("View")
    case .print: PDFName("Print")
    case .export: PDFName("Export")
    }
    let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.identifier, $0) })
    for application in applications {
      guard case .dictionary(let dictionary) = application,
        dictionary.pdfName(named: "Event") == event,
        case .array(let categories)? = dictionary["Category"],
        categories.contains(.name(event))
      else { continue }
      let targets = try optionalContentGroupSet(
        dictionary["OCGs"],
        knownGroups: Set(groupByID.keys)
      )
      for identifier in targets {
        guard let group = groupByID[identifier],
          case .dictionary(let usage)? = group.rawDictionary["Usage"],
          case .dictionary(let category)? = usage[event],
          let stateName = category.pdfName(named: PDFName(String(data: event.bytes, encoding: .ascii)! + "State"))
        else { continue }
        if stateName == PDFName("ON") { states[identifier] = .on }
        if stateName == PDFName("OFF") { states[identifier] = .off }
      }
    }
  }

  private func evaluateOptionalContent(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    states: [PDFOptionalContentGroupIdentifier: PDFOptionalContentState],
    groups: Set<PDFOptionalContentGroupIdentifier>,
    controlling: inout Set<PDFOptionalContentGroupIdentifier>,
    depth: Int
  ) async throws -> Bool {
    guard depth <= limits.maximumOptionalContentExpressionDepth else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "Optional-content expression nesting exceeds its limit."))
    }
    if case .reference(let reference) = object {
      let identifier = PDFOptionalContentGroupIdentifier(reference: reference)
      if groups.contains(identifier) {
        controlling.insert(identifier)
        return states[identifier] != .off
      }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(let value) = resolved.value else {
        throw malformed("An optional-content reference resolves to a stream.")
      }
      return try await evaluateOptionalContent(
        value,
        revision: revision,
        states: states,
        groups: groups,
        controlling: &controlling,
        depth: depth + 1
      )
    }
    guard case .dictionary(let dictionary) = object else {
      throw malformed("Optional content must name an OCG or OCMD dictionary.")
    }
    if dictionary.pdfName(named: "Type") == PDFName("OCG") {
      throw malformed("A direct OCG has no stable document identity.")
    }
    guard dictionary.pdfName(named: "Type") == PDFName("OCMD") || dictionary["OCGs"] != nil || dictionary["VE"] != nil else {
      throw malformed("An optional-content dictionary is not an OCMD.")
    }
    if let expression = dictionary["VE"] {
      return try await evaluateVisibilityExpression(
        expression,
        revision: revision,
        states: states,
        groups: groups,
        controlling: &controlling,
        depth: depth + 1
      )
    }
    let values: [PDFObject]
    switch dictionary["OCGs"] {
    case .array(let array)?: values = array
    case .reference(let reference)?: values = [.reference(reference)]
    case nil: values = []
    default: throw malformed("An OCMD OCGs entry is invalid.")
    }
    var visibility = [Bool]()
    for value in values {
      visibility.append(try await evaluateOptionalContent(
        value,
        revision: revision,
        states: states,
        groups: groups,
        controlling: &controlling,
        depth: depth + 1
      ))
    }
    switch dictionary.pdfName(named: "P") ?? PDFName("AnyOn") {
    case PDFName("AllOn"): return visibility.allSatisfy { $0 }
    case PDFName("AnyOn"): return visibility.contains(true)
    case PDFName("AnyOff"): return visibility.contains(false)
    case PDFName("AllOff"): return visibility.allSatisfy { !$0 }
    default: throw malformed("An OCMD policy is invalid.")
    }
  }

  private func evaluateVisibilityExpression(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    states: [PDFOptionalContentGroupIdentifier: PDFOptionalContentState],
    groups: Set<PDFOptionalContentGroupIdentifier>,
    controlling: inout Set<PDFOptionalContentGroupIdentifier>,
    depth: Int
  ) async throws -> Bool {
    guard case .array(let values) = object, case .name(let operatorName)? = values.first else {
      return try await evaluateOptionalContent(
        object,
        revision: revision,
        states: states,
        groups: groups,
        controlling: &controlling,
        depth: depth
      )
    }
    let operands = values.dropFirst()
    switch operatorName {
    case PDFName("Not"):
      guard operands.count == 1, let operand = operands.first else {
        throw malformed("A Not visibility expression requires one operand.")
      }
      return try await !evaluateVisibilityExpression(
        operand,
        revision: revision,
        states: states,
        groups: groups,
        controlling: &controlling,
        depth: depth + 1
      )
    case PDFName("And"), PDFName("Or"):
      guard !operands.isEmpty else { throw malformed("A visibility expression has no operands.") }
      var results = [Bool]()
      for operand in operands {
        results.append(try await evaluateVisibilityExpression(
          operand,
          revision: revision,
          states: states,
          groups: groups,
          controlling: &controlling,
          depth: depth + 1
        ))
      }
      return operatorName == PDFName("And") ? results.allSatisfy { $0 } : results.contains(true)
    default:
      throw malformed("A visibility expression operator is invalid.")
    }
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }
}
