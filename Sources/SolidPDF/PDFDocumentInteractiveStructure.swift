import Foundation

actor PDFDocumentInteractiveStructure<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let structure: PDFDocumentStructure<Session>
  private let assets: PDFDocumentAssets<Session>
  private let revisions: [PDFDocumentRevision]
  private let limits: PDFParsingLimits
  private var annotationsByPage = [PageKey: [PDFAnnotation]]()
  private var annotationsByIdentifier = [AnnotationKey: PDFAnnotation]()
  private var namedDestinations = [PDFRevisionIdentifier: [PDFDestinationName: PDFDestination]]()
  private var acroForms = [PDFRevisionIdentifier: PDFAcroForm?]()
  private var formFields = [PDFRevisionIdentifier: [PDFFormFieldIdentifier: PDFFormField]]()
  private var validatedAcroForms = Set<PDFRevisionIdentifier>()
  private var closed = false

  init(
    resolver: PDFDocumentResolver<Session>,
    structure: PDFDocumentStructure<Session>,
    assets: PDFDocumentAssets<Session>,
    revisions: [PDFDocumentRevision],
    limits: PDFParsingLimits
  ) {
    self.resolver = resolver
    self.structure = structure
    self.assets = assets
    self.revisions = revisions
    self.limits = limits
  }

  func close() {
    closed = true
    annotationsByPage.removeAll()
    annotationsByIdentifier.removeAll()
    namedDestinations.removeAll()
    acroForms.removeAll()
    formFields.removeAll()
    validatedAcroForms.removeAll()
  }

  func annotations(on page: PDFPage, in revision: PDFRevisionIdentifier) async throws -> [PDFAnnotation] {
    try ensureOpen(revision)
    let key = PageKey(revision: revision, reference: page.reference)
    if let cached = annotationsByPage[key] { return cached }
    guard let raw = page.rawDictionary["Annots"] else {
      annotationsByPage[key] = []
      return []
    }
    let value = try await resolveDirect(raw, revision: revision, visited: [])
    guard case .array(let entries) = value,
      entries.count <= limits.maximumAnnotationsPerPage
    else { throw malformed("A page Annots entry must be a bounded array.") }

    var result = [PDFAnnotation]()
    var seen = Set<PDFObjectReference>()
    var scratch = 0
    for entry in entries {
      guard case .reference(let reference) = entry, seen.insert(reference).inserted else {
        throw malformed("Every page annotation must have a unique indirect identity.")
      }
      let annotation = try await parseAnnotation(reference, page: page, revision: revision)
      result.append(annotation)
      annotationsByIdentifier[AnnotationKey(revision: revision, identifier: annotation.identifier)] = annotation
      scratch = try checkedAdd(scratch, 256 + annotation.rawDictionary.count * 32)
    }
    let pageSet = Set(result.map(\.identifier))
    for annotation in result {
      let payload = annotation.details.payload
      if let popup = payload.popup, !pageSet.contains(popup) {
        throw malformed("An annotation popup is not associated with the same page.")
      }
      if let reply = payload.replyTo, !pageSet.contains(reply) {
        throw malformed("An annotation reply target is not associated with the same page.")
      }
    }
    annotationsByPage[key] = result
    return result
  }

  func annotation(
    _ identifier: PDFAnnotationIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotation {
    try ensureOpen(revision)
    let key = AnnotationKey(revision: revision, identifier: identifier)
    if let cached = annotationsByIdentifier[key] { return cached }
    let pageCount = try await structure.pageCount(in: revision)
    for index in 0..<pageCount {
      let page = try await structure.page(at: index, in: revision)
      _ = try await annotations(on: page, in: revision)
      if let cached = annotationsByIdentifier[key] { return cached }
    }
    throw PDFParsingError.unresolvedReference(identifier.reference)
  }

  func validateAnnotations(in revision: PDFRevisionIdentifier) async throws {
    try ensureOpen(revision)
    let count = try await structure.pageCount(in: revision)
    for index in 0..<count {
      let page = try await structure.page(at: index, in: revision)
      _ = try await annotations(on: page, in: revision)
    }
  }

  func destination(
    named name: PDFDestinationName,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFDestination? {
    try ensureOpen(revision)
    if namedDestinations[revision] == nil {
      namedDestinations[revision] = try await loadNamedDestinations(in: revision)
    }
    return namedDestinations[revision]?[name]
  }

  func acroForm(in revision: PDFRevisionIdentifier) async throws -> PDFAcroForm? {
    try ensureOpen(revision)
    if let cached = acroForms[revision] { return cached }
    let catalog = try await structure.catalog(in: revision)
    guard let raw = catalog.rawDictionary["AcroForm"] else {
      acroForms[revision] = .some(nil)
      return nil
    }
    let (dictionary, definingRevision) = try await resolvedDictionary(raw, revision: revision)
    guard let rawFields = dictionary["Fields"] else {
      throw malformed("An AcroForm dictionary requires Fields.")
    }
    let fieldsObject = try await resolveDirect(rawFields, revision: revision, visited: [])
    guard case .array(let roots) = fieldsObject,
      roots.count <= limits.maximumFormFields
    else { throw malformed("AcroForm Fields must be a bounded array.") }
    let rootIdentifiers = try roots.map { value -> PDFFormFieldIdentifier in
      guard case .reference(let reference) = value else {
        throw malformed("Every root AcroForm field must be indirect.")
      }
      return .init(reference: reference)
    }
    guard Set(rootIdentifiers).count == rootIdentifiers.count else {
      throw malformed("AcroForm Fields contains duplicate roots.")
    }
    let calculationOrder: [PDFFormFieldIdentifier]
    if let rawOrder = dictionary["CO"] {
      let order = try await resolveDirect(rawOrder, revision: revision, visited: [])
      guard case .array(let values) = order else { throw malformed("AcroForm CO must be an array.") }
      calculationOrder = try values.map { value in
        guard case .reference(let reference) = value else {
          throw malformed("Every calculation-order entry must be an indirect field.")
        }
        return .init(reference: reference)
      }
    } else {
      calculationOrder = []
    }
    let defaultResources = try await optionalDictionary(dictionary["DR"], revision: revision)
    let defaultAppearance = try optionalString(dictionary["DA"], name: "DA")
    let justification = try boundedJustification(dictionary.pdfInteger(named: "Q") ?? 0)
    let form = PDFAcroForm(
      fields: rootIdentifiers,
      defaultResources: defaultResources,
      defaultAppearance: defaultAppearance,
      justification: justification,
      calculationOrder: calculationOrder,
      signatureFlags: try nonnegativeInt(dictionary.pdfInteger(named: "SigFlags") ?? 0, name: "SigFlags"),
      needsAppearances: boolean(dictionary["NeedAppearances"]) ?? false,
      xfa: dictionary["XFA"],
      rawDictionary: dictionary,
      definingRevision: definingRevision ?? revision
    )
    acroForms[revision] = form
    return form
  }

  func formFields(in revision: PDFRevisionIdentifier) async throws -> [PDFFormField] {
    guard let form = try await acroForm(in: revision) else { return [] }
    if !validatedAcroForms.contains(revision) {
      try await auditAcroForm(form, revision: revision)
    }
    let fields = formFields[revision] ?? [:]
    return fields.values.sorted { $0.identifier < $1.identifier }
  }

  func formField(
    _ identifier: PDFFormFieldIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFFormField {
    _ = try await formFields(in: revision)
    guard let field = formFields[revision]?[identifier] else {
      throw PDFParsingError.unresolvedReference(identifier.reference)
    }
    return field
  }

  func validateAcroForm(in revision: PDFRevisionIdentifier) async throws {
    _ = try await formFields(in: revision)
  }

  private func auditAcroForm(
    _ form: PDFAcroForm,
    revision: PDFRevisionIdentifier
  ) async throws {
    let pageCount = try await structure.pageCount(in: revision)
    var annotations = [PDFAnnotationIdentifier: PDFAnnotation]()
    for index in 0..<pageCount {
      let page = try await structure.page(at: index, in: revision)
      for annotation in try await self.annotations(on: page, in: revision) {
        annotations[annotation.identifier] = annotation
      }
    }
    var parsed = [PDFFormFieldIdentifier: PDFFormField]()
    var membership = Set<PDFObjectReference>()
    var scratch = 0
    let rootInheritance = FieldInheritance(
      type: nil,
      flags: [],
      value: nil,
      defaultValue: nil,
      actions: [:],
      defaultAppearance: form.defaultAppearance,
      justification: form.justification,
      resources: form.defaultResources
    )
    for root in form.fields {
      try await parseField(
        root,
        expectedParent: nil,
        parentName: nil,
        inheritance: rootInheritance,
        revision: revision,
        annotations: annotations,
        depth: 0,
        ancestry: [],
        membership: &membership,
        parsed: &parsed,
        scratch: &scratch
      )
    }
    for identifier in form.calculationOrder where parsed[identifier] == nil {
      throw malformed("AcroForm CO refers to an object outside the field tree.")
    }
    formFields[revision] = parsed
    validatedAcroForms.insert(revision)
  }

  private func parseField(
    _ identifier: PDFFormFieldIdentifier,
    expectedParent: PDFFormFieldIdentifier?,
    parentName: String?,
    inheritance: FieldInheritance,
    revision: PDFRevisionIdentifier,
    annotations: [PDFAnnotationIdentifier: PDFAnnotation],
    depth: Int,
    ancestry: Set<PDFObjectReference>,
    membership: inout Set<PDFObjectReference>,
    parsed: inout [PDFFormFieldIdentifier: PDFFormField],
    scratch: inout Int
  ) async throws {
    guard depth <= limits.maximumFormFieldDepth else { throw limit("The AcroForm field tree is too deep.") }
    guard membership.insert(identifier.reference).inserted,
      !ancestry.contains(identifier.reference)
    else { throw malformed("The AcroForm field tree contains a cycle or duplicate member.") }
    let object = try await resolver.resolve(identifier.reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = object.value else {
      throw malformed("An AcroForm field must be an ordinary dictionary.")
    }
    let declaredParent = dictionary.pdfReference(named: "Parent").map(PDFFormFieldIdentifier.init(reference:))
    guard declaredParent == expectedParent else { throw malformed("An AcroForm field has an incorrect Parent.") }

    let partialName = try text(dictionary["T"], allowsUTF8: true)
    let fullyQualifiedName = [parentName, partialName].compactMap { $0 }.joined(separator: ".")
    let inherited = try await fieldInheritance(dictionary, parent: inheritance, revision: revision)
    let rawKids: [PDFObject]
    if let raw = dictionary["Kids"] {
      let value = try await resolveDirect(raw, revision: revision, visited: [])
      guard case .array(let values) = value else { throw malformed("A field Kids entry must be an array.") }
      rawKids = values
    } else {
      rawKids = []
    }
    var childIDs = [PDFFormFieldIdentifier]()
    var widgets = [PDFWidget]()
    for kid in rawKids {
      guard case .reference(let reference) = kid else { throw malformed("Every field child must be indirect.") }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let child)) = resolved.value else {
        throw malformed("A field child must be an ordinary dictionary.")
      }
      if child.pdfName(named: "Subtype") == PDFName("Widget"), child["T"] == nil, child["FT"] == nil {
        guard child.pdfReference(named: "Parent") == identifier.reference else {
          throw malformed("A widget child has an incorrect Parent.")
        }
        widgets.append(try widget(reference, dictionary: child, annotations: annotations))
      } else {
        childIDs.append(.init(reference: reference))
      }
    }
    if dictionary.pdfName(named: "Subtype") == PDFName("Widget") {
      widgets.append(try widget(identifier.reference, dictionary: dictionary, annotations: annotations))
    }
    let field = PDFFormField(
      identifier: identifier,
      parent: expectedParent,
      children: childIDs,
      widgets: widgets,
      type: inherited.type,
      flags: inherited.flags,
      partialName: partialName,
      fullyQualifiedName: fullyQualifiedName.isEmpty ? nil : fullyQualifiedName,
      alternateName: try text(dictionary["TU"], allowsUTF8: true),
      mappingName: try text(dictionary["TM"], allowsUTF8: true),
      value: inherited.value,
      defaultValue: inherited.defaultValue,
      options: try await optionalArray(dictionary["Opt"], revision: revision),
      defaultAppearance: inherited.defaultAppearance,
      justification: inherited.justification,
      resources: inherited.resources,
      actions: inherited.actions,
      richTextValue: try optionalString(dictionary["RV"], name: "RV"),
      signature: inherited.type == .signature
        ? try await signature(inherited.value, revision: revision)
        : nil,
      rawDictionary: dictionary,
      definingRevision: object.definitionRevision ?? revision
    )
    parsed[identifier] = field
    scratch = try checkedAdd(scratch, 384 + dictionary.count * 32)
    guard parsed.count <= limits.maximumFormFields else { throw limit("The AcroForm has too many fields.") }
    let nextAncestry = ancestry.union([identifier.reference])
    for child in childIDs {
      try await parseField(
        child,
        expectedParent: identifier,
        parentName: field.fullyQualifiedName,
        inheritance: inherited,
        revision: revision,
        annotations: annotations,
        depth: depth + 1,
        ancestry: nextAncestry,
        membership: &membership,
        parsed: &parsed,
        scratch: &scratch
      )
    }
  }

  private func fieldInheritance(
    _ dictionary: [PDFName: PDFObject],
    parent: FieldInheritance,
    revision: PDFRevisionIdentifier
  ) async throws -> FieldInheritance {
    let type = try dictionary.pdfName(named: "FT").map(fieldType) ?? parent.type
    let rawFlags = dictionary.pdfInteger(named: "Ff")
    let flags: PDFFormFieldFlags
    if let rawFlags {
      guard rawFlags >= 0, rawFlags <= Int64(UInt32.max) else { throw malformed("Field flags are invalid.") }
      flags = .init(rawValue: UInt32(rawFlags))
    } else { flags = parent.flags }
    var actions = parent.actions
    if let rawActions = dictionary["AA"] {
      let actionDictionary = try await optionalDictionary(rawActions, revision: revision) ?? [:]
      for (name, value) in actionDictionary {
        actions[name] = try await parseAction(value, revision: revision, depth: 0, visited: [])
      }
    }
    return FieldInheritance(
      type: type,
      flags: flags,
      value: try formValue(dictionary["V"]) ?? parent.value,
      defaultValue: try formValue(dictionary["DV"]) ?? parent.defaultValue,
      actions: actions,
      defaultAppearance: try optionalString(dictionary["DA"], name: "DA") ?? parent.defaultAppearance,
      justification: try dictionary.pdfInteger(named: "Q").map(boundedJustification) ?? parent.justification,
      resources: try await optionalDictionary(dictionary["DR"], revision: revision) ?? parent.resources
    )
  }

  private func widget(
    _ reference: PDFObjectReference,
    dictionary: [PDFName: PDFObject],
    annotations: [PDFAnnotationIdentifier: PDFAnnotation]
  ) throws -> PDFWidget {
    let identifier = PDFAnnotationIdentifier(reference: reference)
    guard let annotation = annotations[identifier], annotation.subtype == .widget else {
      throw malformed("Every widget must occur in exactly one page annotation array.")
    }
    return PDFWidget(
      annotationIdentifier: identifier,
      pageReference: annotation.pageReference,
      rectangle: annotation.rectangle,
      appearanceState: annotation.appearanceState,
      rawDictionary: dictionary
    )
  }

  private func signature(
    _ value: PDFFormValue?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFSignature? {
    guard let value else { return nil }
    let raw: PDFObject
    switch value {
    case .other(let object): raw = object
    case .null: return nil
    default: throw malformed("A signature field value must be a signature dictionary.")
    }
    let (dictionary, definingRevision) = try await resolvedDictionary(raw, revision: revision)
    guard let byteRange = dictionary.pdfArray(named: "ByteRange"),
      byteRange.count.isMultiple(of: 2),
      byteRange.count / 2 <= limits.maximumSignatureByteRanges,
      case .string(let contents)? = dictionary["Contents"]
    else { throw malformed("A signature requires a bounded ByteRange and Contents.") }
    var ranges = [PDFSourceRange]()
    var previousEnd: Int64 = 0
    for index in stride(from: 0, to: byteRange.count, by: 2) {
      guard case .number(.integer(let offset)) = byteRange[index],
        case .number(.integer(let lengthValue)) = byteRange[index + 1],
        lengthValue >= 0,
        lengthValue <= Int64(Int.max)
      else { throw malformed("A signature ByteRange contains invalid integers.") }
      let range = try PDFSourceRange(offset: offset, length: Int(lengthValue))
      guard range.offset >= previousEnd else { throw malformed("Signature byte ranges overlap or are unsorted.") }
      previousEnd = range.endOffset
      ranges.append(range)
    }
    return PDFSignature(
      byteRanges: ranges,
      contents: contents.bytes,
      filter: dictionary.pdfName(named: "Filter"),
      subfilter: dictionary.pdfName(named: "SubFilter"),
      reason: try text(dictionary["Reason"], allowsUTF8: true),
      signingTime: try optionalString(dictionary["M"], name: "M"),
      permissions: dictionary["Reference"],
      rawDictionary: dictionary,
      definingRevision: definingRevision ?? revision
    )
  }

  private func fieldType(_ name: PDFName) throws -> PDFFormFieldType {
    switch name {
    case "Btn": .button
    case "Tx": .text
    case "Ch": .choice
    case "Sig": .signature
    default: throw malformed("A field has an unknown FT value.")
    }
  }

  private func formValue(_ object: PDFObject?) throws -> PDFFormValue? {
    guard let object else { return nil }
    return switch object {
    case .string(let value): .string(value)
    case .name(let value): .name(value)
    case .array(let values):
      .strings(try values.map { value in
        guard case .string(let string) = value else { throw malformed("A multiselect field value must contain strings.") }
        return string
      })
    case .null: .null
    default: .other(object)
    }
  }

  private func resolvedDictionary(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier
  ) async throws -> ([PDFName: PDFObject], PDFRevisionIdentifier?) {
    if case .reference(let reference) = object {
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let dictionary)) = resolved.value else {
        throw malformed("The referenced value must be an ordinary dictionary.")
      }
      return (dictionary, resolved.definitionRevision)
    }
    guard case .dictionary(let dictionary) = object else { throw malformed("The value must be a dictionary.") }
    return (dictionary, nil)
  }

  private func optionalDictionary(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> [PDFName: PDFObject]? {
    guard let object else { return nil }
    let direct = try await resolveDirect(object, revision: revision, visited: [])
    guard case .dictionary(let dictionary) = direct else { throw malformed("The value must be a dictionary.") }
    return dictionary
  }

  private func optionalArray(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> [PDFObject] {
    guard let object else { return [] }
    let direct = try await resolveDirect(object, revision: revision, visited: [])
    guard case .array(let values) = direct else { throw malformed("The value must be an array.") }
    return values
  }

  private func optionalString(_ object: PDFObject?, name: PDFName) throws -> PDFString? {
    guard let object else { return nil }
    guard case .string(let value) = object else { throw malformed("\(name) must be a string.") }
    return value
  }

  private func boundedJustification(_ value: Int64) throws -> Int {
    guard 0...2 ~= value else { throw malformed("Field justification must be 0, 1, or 2.") }
    return Int(value)
  }

  private func nonnegativeInt(_ value: Int64, name: PDFName) throws -> Int {
    guard value >= 0, value <= Int64(Int.max) else { throw malformed("\(name) is outside its supported range.") }
    return Int(value)
  }

  private func parseAnnotation(
    _ reference: PDFObjectReference,
    page: PDFPage,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotation {
    let object = try await resolver.resolve(reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = object.value,
      dictionary.pdfName(named: "Type").map({ $0 == PDFName("Annot") }) ?? true,
      let subtypeName = dictionary.pdfName(named: "Subtype")
    else { throw malformed("An annotation must be an ordinary annotation dictionary with a Subtype.") }
    if let associatedPage = dictionary.pdfReference(named: "P"), associatedPage != page.reference {
      throw malformed("An annotation's P entry does not identify its containing page.")
    }
    let rectangle = try parseRectangle(dictionary["Rect"])
    let flagsValue = dictionary.pdfInteger(named: "F") ?? 0
    guard flagsValue >= 0, flagsValue <= Int64(UInt32.max) else {
      throw malformed("Annotation flags are outside the unsigned 32-bit range.")
    }
    let subtype = PDFAnnotationSubtype(name: subtypeName)
    let payload = try await parsePayload(dictionary, revision: revision)
    let allowsUTF8 = try await structure.catalog(in: revision).effectiveVersion == .v2_0
    return PDFAnnotation(
      identifier: .init(reference: reference),
      subtype: subtype,
      pageReference: page.reference,
      rectangle: rectangle,
      flags: .init(rawValue: UInt32(flagsValue)),
      contents: try text(dictionary["Contents"], allowsUTF8: allowsUTF8),
      alternateDescription: try text(dictionary["Alt"], allowsUTF8: allowsUTF8),
      title: try text(dictionary["T"], allowsUTF8: allowsUTF8),
      uniqueName: dictionary["NM"].flatMap { if case .string(let value) = $0 { value } else { nil } },
      appearanceState: dictionary.pdfName(named: "AS"),
      appearances: try await parseAppearances(dictionary["AP"], revision: revision),
      optionalContent: dictionary["OC"],
      details: details(subtype: subtype, payload: payload),
      rawDictionary: dictionary,
      definingRevision: object.definitionRevision ?? revision
    )
  }

  private func parsePayload(
    _ dictionary: [PDFName: PDFObject],
    revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotationPayload {
    let action = try await parseOptionalAction(dictionary["A"], revision: revision)
    let destination = try await parseOptionalDestination(dictionary["Dest"], revision: revision)
    let fileSpecification: PDFFileSpecification?
    if let object = dictionary["FS"] {
      fileSpecification = try await assets.fileSpecification(object, in: revision)
    } else {
      fileSpecification = nil
    }
    return PDFAnnotationPayload(
      points: try numberArray(dictionary["QuadPoints"] ?? dictionary["Vertices"] ?? dictionary["L"]),
      inkLists: try numberArrays(dictionary["InkList"]),
      destination: destination,
      action: action,
      popup: dictionary.pdfReference(named: "Popup").map(PDFAnnotationIdentifier.init(reference:)),
      replyTo: dictionary.pdfReference(named: "IRT").map(PDFAnnotationIdentifier.init(reference:)),
      replyType: dictionary.pdfName(named: "RT"),
      fileSpecification: fileSpecification,
      extensions: dictionary
    )
  }

  private func details(
    subtype: PDFAnnotationSubtype,
    payload: PDFAnnotationPayload
  ) -> PDFAnnotationDetails {
    switch subtype {
    case .text: .text(payload)
    case .link: .link(payload)
    case .freeText: .freeText(payload)
    case .line: .line(payload)
    case .square: .square(payload)
    case .circle: .circle(payload)
    case .polygon: .polygon(payload)
    case .polyLine: .polyLine(payload)
    case .highlight: .highlight(payload)
    case .underline: .underline(payload)
    case .squiggly: .squiggly(payload)
    case .strikeOut: .strikeOut(payload)
    case .stamp: .stamp(payload)
    case .caret: .caret(payload)
    case .ink: .ink(payload)
    case .popup: .popup(payload)
    case .fileAttachment: .fileAttachment(payload)
    case .sound: .sound(payload)
    case .movie: .movie(payload)
    case .widget: .widget(payload)
    case .screen: .screen(payload)
    case .printerMark: .printerMark(payload)
    case .trapNet: .trapNet(payload)
    case .watermark: .watermark(payload)
    case .threeD: .threeD(payload)
    case .redact: .redact(payload)
    case .projection: .projection(payload)
    case .richMedia: .richMedia(payload)
    case .unknown(let name): .unknown(name, payload)
    }
  }

  private func parseAppearances(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotationAppearances {
    guard let object else { return .init() }
    let direct = try await resolveDirect(object, revision: revision, visited: [])
    guard case .dictionary(let dictionary) = direct else {
      throw malformed("An annotation AP entry must be a dictionary.")
    }
    return try await .init(
      normal: parseAppearance(dictionary["N"], revision: revision),
      rollover: parseAppearance(dictionary["R"], revision: revision),
      down: parseAppearance(dictionary["D"], revision: revision)
    )
  }

  private func parseAppearance(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotationAppearance? {
    guard let object else { return nil }
    if case .reference(let reference) = object {
      let resolved = try await resolver.resolve(reference, in: revision)
      if case .stream(let stream) = resolved.value { return .stream(stream) }
    }
    let direct = try await resolveDirect(object, revision: revision, visited: [])
    guard case .dictionary(let dictionary) = direct,
      dictionary.count <= limits.maximumAnnotationAppearanceStates
    else { throw malformed("An annotation appearance must be a stream or bounded state dictionary.") }
    var states = [PDFName: PDFStreamObject]()
    for (name, value) in dictionary {
      guard case .reference(let reference) = value else {
        throw malformed("An annotation appearance state must identify an indirect stream.")
      }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .stream(let stream) = resolved.value else {
        throw malformed("An annotation appearance state must identify a stream.")
      }
      states[name] = stream
    }
    return .states(states)
  }

  private func loadNamedDestinations(
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFDestinationName: PDFDestination] {
    let catalog = try await structure.catalog(in: revision)
    var result = [PDFDestinationName: PDFDestination]()
    if let rawDests = catalog.rawDictionary["Dests"] {
      let direct = try await resolveDirect(rawDests, revision: revision, visited: [])
      guard case .dictionary(let dictionary) = direct else {
        throw malformed("Catalog Dests must be a dictionary.")
      }
      for (name, value) in dictionary {
        result[.name(name)] = try await parseDestination(value, revision: revision)
      }
    }
    if let rawNames = catalog.rawDictionary["Names"] {
      let direct = try await resolveDirect(rawNames, revision: revision, visited: [])
      guard case .dictionary(let names) = direct else {
        throw malformed("Catalog Names must be a dictionary.")
      }
      if let tree = names["Dests"] {
        let entries = try await PDFCollectionTreeReader(
          kind: .name,
          limits: limits,
          resolve: { [resolver] reference in try await resolver.resolve(reference, in: revision) }
        ).read(tree)
        for entry in entries {
          guard case .name(let bytes) = entry.key else { continue }
          let key = PDFDestinationName.string(.init(bytes: bytes))
          guard result[key] == nil else { throw malformed("A named destination is duplicated.") }
          result[key] = try await parseDestination(entry.value, revision: revision)
        }
      }
    }
    return result
  }

  private func parseOptionalDestination(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFDestination? {
    guard let object else { return nil }
    return try await parseDestination(object, revision: revision)
  }

  private func parseDestination(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFDestination {
    let value = try await resolveDirect(object, revision: revision, visited: [])
    switch value {
    case .name(let name): return .named(.name(name))
    case .string(let string): return .named(.string(string))
    case .dictionary(let dictionary):
      guard let destination = dictionary["D"] else {
        throw malformed("A destination dictionary requires D.")
      }
      return try await parseDestination(destination, revision: revision)
    case .array(let values):
      guard values.count >= 2, case .name(let kind) = values[1] else {
        throw malformed("An explicit destination requires a page and destination type.")
      }
      return .explicit(page: values[0], view: try destinationView(kind, values: Array(values.dropFirst(2))))
    default:
      throw malformed("A destination has an invalid type.")
    }
  }

  private func destinationView(_ name: PDFName, values: [PDFObject]) throws -> PDFDestinationView {
    func optionalNumber(_ index: Int) throws -> Double? {
      guard index < values.count else { return nil }
      if case .null = values[index] { return nil }
      return try number(values[index])
    }
    switch name {
    case "XYZ": return .xyz(left: try optionalNumber(0), top: try optionalNumber(1), zoom: try optionalNumber(2))
    case "Fit": return .fit
    case "FitH": return .fitHorizontal(top: try optionalNumber(0))
    case "FitV": return .fitVertical(left: try optionalNumber(0))
    case "FitR":
      guard values.count == 4 else { throw malformed("FitR requires four coordinates.") }
      return .fitRectangle(try PDFRectangle(
        x1: number(values[0]), y1: number(values[1]), x2: number(values[2]), y2: number(values[3])
      ))
    case "FitB": return .fitBoundingBox
    case "FitBH": return .fitBoundingBoxHorizontal(top: try optionalNumber(0))
    case "FitBV": return .fitBoundingBoxVertical(left: try optionalNumber(0))
    default: throw malformed("An explicit destination uses an unknown destination type.")
    }
  }

  private func parseOptionalAction(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFAction? {
    guard let object else { return nil }
    return try await parseAction(object, revision: revision, depth: 0, visited: [])
  }

  private func parseAction(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    depth: Int,
    visited: Set<PDFObjectReference>
  ) async throws -> PDFAction {
    guard depth < limits.maximumActionChainLength else {
      throw limit("An action chain exceeds its configured limit.")
    }
    var nextVisited = visited
    let dictionary: [PDFName: PDFObject]
    if case .reference(let reference) = object {
      guard nextVisited.insert(reference).inserted else {
        throw PDFParsingError.referenceCycle(Array(visited) + [reference])
      }
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let value)) = resolved.value else {
        throw malformed("An action reference must identify an ordinary dictionary.")
      }
      dictionary = value
    } else {
      let direct = try await resolveDirect(object, revision: revision, visited: [])
      guard case .dictionary(let value) = direct else { throw malformed("An action must be a dictionary.") }
      dictionary = value
    }
    guard let subtype = dictionary.pdfName(named: "S") else { throw malformed("An action requires S.") }
    let kind = try await actionKind(subtype, dictionary: dictionary, revision: revision)
    let rawNext: [PDFObject]
    switch dictionary["Next"] {
    case nil: rawNext = []
    case .array(let values): rawNext = values
    case .some(let value): rawNext = [value]
    }
    var next = [PDFAction]()
    for value in rawNext {
      next.append(try await parseAction(
        value, revision: revision, depth: depth + 1, visited: nextVisited
      ))
    }
    return .init(kind: kind, next: next, rawDictionary: dictionary)
  }

  private func actionKind(
    _ subtype: PDFName,
    dictionary: [PDFName: PDFObject],
    revision: PDFRevisionIdentifier
  ) async throws -> PDFActionKind {
    func required(_ name: PDFName) throws -> PDFObject {
      guard let value = dictionary[name] else { throw malformed("Action \(name) is required.") }
      return value
    }
    switch subtype {
    case "GoTo": return .goTo(try await parseDestination(required("D"), revision: revision))
    case "GoToR": return .goToRemote(
      file: try required("F"), destination: try await parseOptionalDestination(dictionary["D"], revision: revision),
      newWindow: boolean(dictionary["NewWindow"])
    )
    case "GoToE": return .goToEmbedded(
      file: dictionary["F"], target: try required("T"),
      destination: try await parseOptionalDestination(dictionary["D"], revision: revision),
      newWindow: boolean(dictionary["NewWindow"])
    )
    case "Launch": return .launch(file: dictionary["F"], platformParameters: dictionary["Win"])
    case "Thread": return .thread(file: dictionary["F"], thread: try required("D"), bead: dictionary["B"])
    case "URI":
      guard case .string(let uri) = try required("URI") else { throw malformed("URI must be a string.") }
      return .uri(uri, isMap: boolean(dictionary["IsMap"]) ?? false)
    case "Sound": return .sound(try required("Sound"))
    case "Movie": return .movie(
      annotation: dictionary["Annotation"],
      title: dictionary["T"].flatMap { if case .string(let value) = $0 { value } else { nil } },
      operation: dictionary.pdfName(named: "Operation")
    )
    case "Hide": return .hide(target: try required("T"), hidden: boolean(dictionary["H"]) ?? true)
    case "Named":
      guard let name = dictionary.pdfName(named: "N") else { throw malformed("Named action requires N.") }
      return .named(name)
    case "SubmitForm": return .submitForm(
      file: try required("F"), fields: array(dictionary["Fields"]), flags: dictionary.pdfInteger(named: "Flags") ?? 0
    )
    case "ResetForm": return .resetForm(
      fields: array(dictionary["Fields"]), flags: dictionary.pdfInteger(named: "Flags") ?? 0
    )
    case "ImportData": return .importData(try required("F"))
    case "JavaScript": return .javaScript(try required("JS"))
    case "SetOCGState": return .setOptionalContentState(
      array(dictionary["State"]), preserveRadioButtonState: boolean(dictionary["PreserveRB"]) ?? true
    )
    case "Rendition": return .rendition(dictionary["R"] ?? .null)
    case "Trans": return .transition(dictionary["Trans"] ?? .null)
    case "GoTo3DView": return .goToThreeDView(annotation: try required("TA"), view: try required("V"))
    default: return .unknown(subtype)
    }
  }

  private func resolveDirect(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    visited: Set<PDFObjectReference>
  ) async throws -> PDFObject {
    guard case .reference(let reference) = object else { return object }
    guard !visited.contains(reference) else {
      throw PDFParsingError.referenceCycle(Array(visited) + [reference])
    }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .value(let value) = resolved.value else {
      throw malformed("A direct value unexpectedly resolves to a stream.")
    }
    return try await resolveDirect(value, revision: revision, visited: visited.union([reference]))
  }

  private func parseRectangle(_ object: PDFObject?) throws -> PDFRectangle {
    guard case .array(let values)? = object, values.count == 4 else {
      throw malformed("An annotation Rect must contain four numbers.")
    }
    return try PDFRectangle(
      x1: number(values[0]), y1: number(values[1]), x2: number(values[2]), y2: number(values[3])
    )
  }

  private func number(_ object: PDFObject) throws -> Double {
    switch object {
    case .number(.integer(let value)): Double(value)
    case .number(.real(let value)) where value.isFinite: value
    default: throw malformed("A numeric annotation value is malformed.")
    }
  }

  private func numberArray(_ object: PDFObject?) throws -> [Double] {
    guard let object else { return [] }
    guard case .array(let values) = object else { throw malformed("An annotation coordinate entry must be an array.") }
    return try values.map(number)
  }

  private func numberArrays(_ object: PDFObject?) throws -> [[Double]] {
    guard let object else { return [] }
    guard case .array(let arrays) = object else { throw malformed("InkList must be an array.") }
    return try arrays.map { value in
      guard case .array(let values) = value else { throw malformed("Each InkList path must be an array.") }
      return try values.map(number)
    }
  }

  private func text(_ object: PDFObject?, allowsUTF8: Bool) throws -> String? {
    guard let object else { return nil }
    guard case .string(let value) = object else { throw malformed("An annotation text entry must be a string.") }
    return try PDFTextStringDecoder.decode(value, allowsUTF8: allowsUTF8)
  }

  private func boolean(_ object: PDFObject?) -> Bool? {
    guard case .boolean(let value)? = object else { return nil }
    return value
  }

  private func array(_ object: PDFObject?) -> [PDFObject] {
    guard case .array(let values)? = object else { return [] }
    return values
  }

  private func ensureOpen(_ revision: PDFRevisionIdentifier) throws {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard revisions.contains(where: { $0.identifier == revision }) else {
      throw PDFParsingError.unknownRevision(revision)
    }
  }

  private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, value <= limits.maximumInteractiveStructureScratchBytes else {
      throw limit("Annotation processing exceeds its scratch limit.")
    }
    return value
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  private func limit(_ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: 0, message: message))
  }
}

private struct PageKey: Hashable {
  let revision: PDFRevisionIdentifier
  let reference: PDFObjectReference
}

private struct AnnotationKey: Hashable {
  let revision: PDFRevisionIdentifier
  let identifier: PDFAnnotationIdentifier
}

private struct FieldInheritance {
  let type: PDFFormFieldType?
  let flags: PDFFormFieldFlags
  let value: PDFFormValue?
  let defaultValue: PDFFormValue?
  let actions: [PDFName: PDFAction]
  let defaultAppearance: PDFString?
  let justification: Int
  let resources: [PDFName: PDFObject]?
}
