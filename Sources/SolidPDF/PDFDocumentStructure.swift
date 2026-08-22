actor PDFDocumentStructure<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let revisions: [PDFDocumentRevision]
  private let headerVersion: PDFFileVersion
  private let limits: PDFParsingLimits
  private var catalogs = [PDFRevisionIdentifier: PDFDocumentCatalog]()
  private var validatedPageCounts = [PDFRevisionIdentifier: Int]()
  private var pendingPageValidations = [PDFRevisionIdentifier: Task<Int, Error>]()
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
    return PDFPage(
      index: index,
      reference: reference,
      rawDictionary: dictionary,
      definingRevision: object.definitionRevision ?? revision,
      ancestorReferences: ancestors,
      resources: resources,
      geometry: geometry
    )
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

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }
}
