import Foundation

actor PDFDocumentAssets<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let structure: PDFDocumentStructure<Session>
  private let revisions: [PDFDocumentRevision]
  private let limits: PDFParsingLimits
  private var metadataCache = [PDFRevisionIdentifier: PDFMetadata]()
  private var fileSpecificationCache = [FileKey: PDFFileSpecification]()
  private var embeddedFileCache = [PDFRevisionIdentifier: [PDFEmbeddedFile]]()
  private var collectionCache = [PDFRevisionIdentifier: PDFCollection?]()
  private var closed = false

  init(
    resolver: PDFDocumentResolver<Session>,
    structure: PDFDocumentStructure<Session>,
    revisions: [PDFDocumentRevision],
    limits: PDFParsingLimits
  ) {
    self.resolver = resolver
    self.structure = structure
    self.revisions = revisions
    self.limits = limits
  }

  func close() {
    closed = true
    metadataCache.removeAll()
    fileSpecificationCache.removeAll()
    embeddedFileCache.removeAll()
    collectionCache.removeAll()
  }

  func metadata(in revision: PDFRevisionIdentifier) async throws -> PDFMetadata {
    try ensureOpen(revision)
    if let cached = metadataCache[revision] { return cached }
    guard let revisionValue = revisions.first(where: { $0.identifier == revision }) else {
      throw PDFParsingError.unknownRevision(revision)
    }
    let catalog = try await structure.catalog(in: revision)
    let allowsUTF8 = catalog.effectiveVersion == .v2_0
    let information = try await parseInformation(
      reference: revisionValue.info,
      revision: revision,
      allowsUTF8: allowsUTF8
    )
    let xmp = try await parseXMP(catalog: catalog, revision: revision)
    let result = reconcile(information: information, xmp: xmp)
    metadataCache[revision] = result
    return result
  }

  func fileSpecification(
    _ object: PDFObject,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFFileSpecification {
    try ensureOpen(revision)
    let reference: PDFObjectReference?
    let value: PDFObject
    let definingRevision: PDFRevisionIdentifier
    if case .reference(let indirectReference) = object {
      let key = FileKey(revision: revision, reference: indirectReference)
      if let cached = fileSpecificationCache[key] { return cached }
      let resolved = try await resolver.resolve(indirectReference, in: revision)
      guard case .value(let direct) = resolved.value else {
        throw malformed("A file specification cannot be a stream object.")
      }
      reference = indirectReference
      value = direct
      definingRevision = resolved.definitionRevision ?? revision
    } else {
      reference = nil
      value = object
      definingRevision = revision
    }
    let result = try parseFileSpecification(
      value,
      reference: reference,
      revision: revision,
      definingRevision: definingRevision,
      allowsUTF8: try await structure.catalog(in: revision).effectiveVersion == .v2_0
    )
    if let reference {
      guard fileSpecificationCache.count < limits.maximumFileSpecifications else {
        throw limit("The document contains too many retained file specifications.")
      }
      fileSpecificationCache[FileKey(revision: revision, reference: reference)] = result
    }
    return result
  }

  func embeddedFiles(in revision: PDFRevisionIdentifier) async throws -> [PDFEmbeddedFile] {
    try ensureOpen(revision)
    if let cached = embeddedFileCache[revision] { return cached }
    let catalog = try await structure.catalog(in: revision)
    guard let rawNames = catalog.rawDictionary["Names"] else {
      embeddedFileCache[revision] = []
      return []
    }
    let names = try await requiredDictionary(rawNames, revision: revision, description: "Catalog Names")
    guard let tree = names["EmbeddedFiles"] else {
      embeddedFileCache[revision] = []
      return []
    }
    let entries = try await PDFCollectionTreeReader(
      kind: .name,
      limits: limits,
      resolve: { [resolver] reference in try await resolver.resolve(reference, in: revision) }
    ).read(tree)
    guard entries.count <= limits.maximumEmbeddedFileEntries else {
      throw limit("The EmbeddedFiles tree exceeds its configured entry limit.")
    }
    var files = [PDFEmbeddedFile]()
    files.reserveCapacity(entries.count)
    var seenSpecifications = Set<PDFFileSpecificationIdentifier>()
    for entry in entries {
      guard case .name(let key) = entry.key else { continue }
      let specification = try await fileSpecification(entry.value, in: revision)
      guard seenSpecifications.insert(specification.identifier).inserted else {
        throw malformed("The EmbeddedFiles tree contains a duplicate file specification.")
      }
      files.append(try await embeddedFile(
        for: specification,
        nameTreeKey: .init(bytes: key),
        revision: revision
      ))
    }
    embeddedFileCache[revision] = files
    return files
  }

  func associatedFiles(
    owner: PDFAssociatedFileOwner,
    objects: [PDFObject],
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFAssociatedFile] {
    guard objects.count <= limits.maximumFileSpecifications else {
      throw limit("An associated-file array exceeds its configured limit.")
    }
    var result = [PDFAssociatedFile]()
    result.reserveCapacity(objects.count)
    for object in objects {
      let specification = try await fileSpecification(object, in: revision)
      let relationship: PDFAssociatedFileRelationship
      if case .dictionary(let dictionary) = specification.rawObject {
        relationship = .init(dictionary.pdfName(named: "AFRelationship"))
      } else {
        relationship = .unspecified
      }
      result.append(.init(
        fileSpecification: specification,
        relationship: relationship,
        owner: owner,
        revision: revision
      ))
    }
    return result
  }

  func catalogAssociatedFiles(in revision: PDFRevisionIdentifier) async throws -> [PDFAssociatedFile] {
    let catalog = try await structure.catalog(in: revision)
    guard let object = catalog.rawDictionary["AF"] else { return [] }
    let direct = try await resolveDirect(object, revision: revision, visited: [])
    guard case .array(let values) = direct else {
      throw malformed("Catalog AF must be an array of file specifications.")
    }
    return try await associatedFiles(owner: .catalog(catalog.reference), objects: values, in: revision)
  }

  func collection(in revision: PDFRevisionIdentifier) async throws -> PDFCollection? {
    try ensureOpen(revision)
    if let cached = collectionCache[revision] { return cached }
    let catalog = try await structure.catalog(in: revision)
    guard let raw = catalog.rawDictionary["Collection"] else {
      collectionCache[revision] = .some(nil)
      return nil
    }
    let (dictionary, definingRevision) = try await resolvedDictionary(
      raw,
      revision: revision,
      description: "Catalog Collection"
    )
    let schema = try await collectionSchema(dictionary["Schema"], revision: revision)
    let files = try await embeddedFiles(in: revision)
    var items = [PDFCollectionItem]()
    for file in files where file.fileSpecification.collectionItem != nil {
      items.append(.init(
        fileSpecification: file.fileSpecification.identifier,
        values: file.fileSpecification.collectionItem ?? [:]
      ))
    }
    let result = PDFCollection(
      view: collectionView(dictionary.pdfName(named: "View")),
      initialDocument: try optionalString(dictionary["D"], name: "D"),
      schema: schema,
      items: items,
      sort: try await collectionSort(dictionary["Sort"], schema: schema, revision: revision),
      rawDictionary: dictionary,
      definingRevision: definingRevision
    )
    collectionCache[revision] = result
    return result
  }

  private struct Information {
    let dictionary: [PDFName: PDFObject]?
    let definingRevision: PDFRevisionIdentifier?
    let values: [String: String]
    let dates: [String: PDFDate]
    let custom: [PDFName: PDFString]
    let diagnostics: [PDFMetadataDiagnostic]
  }

  private func parseInformation(
    reference: PDFObjectReference?,
    revision: PDFRevisionIdentifier,
    allowsUTF8: Bool
  ) async throws -> Information {
    guard let reference else {
      return Information(dictionary: nil, definingRevision: nil, values: [:], dates: [:], custom: [:], diagnostics: [])
    }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = resolved.value else {
      throw malformed("The document Info entry must identify an ordinary dictionary.")
    }
    let textKeys: Set<PDFName> = ["Title", "Author", "Subject", "Keywords", "Creator", "Producer"]
    let dateKeys: Set<PDFName> = ["CreationDate", "ModDate"]
    var values = [String: String]()
    var dates = [String: PDFDate]()
    var custom = [PDFName: PDFString]()
    var diagnostics = [PDFMetadataDiagnostic]()
    for (key, object) in dictionary {
      if textKeys.contains(key) {
        guard case .string(let string) = object else { throw malformed("An Info text entry must be a string.") }
        values[String(decoding: key.bytes, as: UTF8.self)] = try PDFTextStringDecoder.decode(string, allowsUTF8: allowsUTF8)
      } else if dateKeys.contains(key) {
        guard case .string(let string) = object else { throw malformed("An Info date entry must be a string.") }
        do {
          dates[String(decoding: key.bytes, as: UTF8.self)] = try PDFDate(string)
        } catch {
          diagnostics.append(.init(field: String(decoding: key.bytes, as: UTF8.self), message: "The Info date is malformed and was not reconciled."))
        }
      } else if key != "Trapped", case .string(let string) = object {
        custom[key] = string
      }
    }
    return Information(
      dictionary: dictionary,
      definingRevision: resolved.definitionRevision ?? revision,
      values: values,
      dates: dates,
      custom: custom,
      diagnostics: diagnostics
    )
  }

  private func parseXMP(
    catalog: PDFDocumentCatalog,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFXMPPacket? {
    guard let object = catalog.rawDictionary["Metadata"] else { return nil }
    guard case .reference(let reference) = object else {
      throw malformed("Catalog Metadata must identify an indirect metadata stream.")
    }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .stream(let stream) = resolved.value,
      stream.dictionary.pdfName(named: "Type") == "Metadata",
      stream.dictionary.pdfName(named: "Subtype") == "XML"
    else { throw malformed("Catalog Metadata must be an XML metadata stream.") }
    let bytes = try await resolver.decodedBytes(stream)
    guard bytes.count <= limits.maximumMetadataPacketBytes else {
      throw limit("An XMP packet exceeds its configured byte limit.")
    }
    let properties = try PDFXMPParser(limits: limits).parse(bytes)
    return PDFXMPPacket(
      bytes: bytes,
      properties: properties,
      streamReference: reference,
      definingRevision: resolved.definitionRevision ?? revision
    )
  }

  private func reconcile(information: Information, xmp: PDFXMPPacket?) -> PDFMetadata {
    let xmpValues = Dictionary(grouping: xmp?.properties ?? [], by: { Self.localName($0.qualifiedName) })
      .compactMapValues { $0.first?.value }
    var diagnostics = information.diagnostics
    let informationModified = information.dates["ModDate"]
    let xmpModified = xmpValues["ModifyDate"].flatMap(Self.parseXMPDate)
    let preferXMP: Bool?
    if let infoInstant = informationModified?.instant, let xmpInstant = xmpModified?.instant {
      preferXMP = xmpInstant >= infoInstant
    } else if informationModified != nil || xmpModified != nil {
      preferXMP = nil
      diagnostics.append(.init(field: "ModDate", message: "Metadata timestamps are incomplete or incomparable; both sources were retained."))
    } else {
      preferXMP = xmp != nil
    }

    func string(_ infoKey: String, _ xmpKey: String) -> PDFMetadataProperty<String>? {
      let info = information.values[infoKey]
      let xmp = xmpValues[xmpKey] ?? nil
      if preferXMP != false, let xmp { return .init(value: xmp, source: .xmp) }
      if let info { return .init(value: info, source: .informationDictionary) }
      if let xmp { return .init(value: xmp, source: .xmp) }
      return nil
    }
    func date(_ infoKey: String, _ xmpKey: String) -> PDFMetadataProperty<PDFDate>? {
      let info = information.dates[infoKey]
      let xmp = xmpValues[xmpKey].flatMap(Self.parseXMPDate)
      if preferXMP != false, let xmp { return .init(value: xmp, source: .xmp) }
      if let info { return .init(value: info, source: .informationDictionary) }
      if let xmp { return .init(value: xmp, source: .xmp) }
      return nil
    }
    return PDFMetadata(
      fields: .init(
        title: string("Title", "title"),
        author: string("Author", "creator"),
        subject: string("Subject", "description"),
        keywords: string("Keywords", "Keywords"),
        creator: string("Creator", "CreatorTool"),
        producer: string("Producer", "Producer"),
        creationDate: date("CreationDate", "CreateDate"),
        modificationDate: date("ModDate", "ModifyDate")
      ),
      informationDictionary: information.dictionary,
      informationRevision: information.definingRevision,
      customInformation: information.custom,
      xmp: xmp,
      diagnostics: diagnostics
    )
  }

  private func parseFileSpecification(
    _ object: PDFObject,
    reference: PDFObjectReference?,
    revision: PDFRevisionIdentifier,
    definingRevision: PDFRevisionIdentifier,
    allowsUTF8: Bool
  ) throws -> PDFFileSpecification {
    let identifier = PDFFileSpecificationIdentifier(reference: reference, revision: revision, directObject: reference == nil ? object : nil)
    if case .string(let filename) = object {
      return PDFFileSpecification(
        identifier: identifier,
        filename: filename,
        rawObject: object,
        definingRevision: definingRevision
      )
    }
    guard case .dictionary(let dictionary) = object,
      dictionary.pdfName(named: "Type").map({ $0 == PDFName("Filespec") }) ?? true
    else { throw malformed("A file specification must be a string or Filespec dictionary.") }
    let filename = try optionalString(dictionary["F"], name: "F")
    let unicode = try optionalString(dictionary["UF"], name: "UF")
    let identifiers: [PDFString]?
    if let raw = dictionary["ID"] {
      guard case .array(let values) = raw, values.count == 2 else {
        throw malformed("A file specification ID must contain two strings.")
      }
      identifiers = try values.map { value in
        guard case .string(let string) = value else { throw malformed("A file specification ID must contain strings.") }
        return string
      }
    } else { identifiers = nil }
    let embedded: [PDFName: PDFObject]
    if let raw = dictionary["EF"] {
      guard case .dictionary(let values) = raw else { throw malformed("A file specification EF entry must be a dictionary.") }
      embedded = values
    } else { embedded = [:] }
    let collectionItem: [PDFName: PDFObject]?
    if let raw = dictionary["CI"] {
      guard case .dictionary(let value) = raw else { throw malformed("A file specification CI entry must be a dictionary.") }
      collectionItem = value
    } else { collectionItem = nil }
    let isVolatile: Bool = if case .boolean(let value)? = dictionary["V"] { value } else { false }
    return PDFFileSpecification(
      identifier: identifier,
      fileSystem: dictionary.pdfName(named: "FS"),
      filename: filename,
      unicodeFilename: try unicode.map { try PDFTextStringDecoder.decode($0, allowsUTF8: allowsUTF8) },
      identifiers: identifiers,
      isVolatile: isVolatile,
      description: try optionalString(dictionary["Desc"], name: "Desc").map { try PDFTextStringDecoder.decode($0, allowsUTF8: allowsUTF8) },
      relatedFiles: dictionary["RF"],
      collectionItem: collectionItem,
      embeddedFileEntries: embedded,
      rawObject: object,
      definingRevision: definingRevision
    )
  }

  private func embeddedFile(
    for specification: PDFFileSpecification,
    nameTreeKey: PDFString?,
    revision: PDFRevisionIdentifier
  ) async throws -> PDFEmbeddedFile {
    guard !specification.embeddedFileEntries.isEmpty else {
      throw malformed("An EmbeddedFiles entry does not provide an EF stream.")
    }
    let preferredKeys: [PDFName] = specification.unicodeFilename == nil
      ? ["F", "UF", "DOS", "Mac", "Unix"]
      : ["UF", "F", "DOS", "Mac", "Unix"]
    guard let object = preferredKeys.lazy.compactMap({ specification.embeddedFileEntries[$0] }).first,
      case .reference(let reference) = object
    else { throw malformed("An embedded-file entry must identify an indirect stream.") }
    let resolved = try await resolver.resolve(reference, in: revision)
    guard case .stream(let stream) = resolved.value,
      stream.dictionary.pdfName(named: "Type").map({ $0 == PDFName("EmbeddedFile") }) ?? true
    else { throw malformed("An EF entry must identify an EmbeddedFile stream.") }
    let parameters: [PDFName: PDFObject]
    if let raw = stream.dictionary["Params"] {
      parameters = try await requiredDictionary(raw, revision: revision, description: "EmbeddedFile Params")
    } else { parameters = [:] }
    let declaredSize: Int?
    if let rawSize = parameters["Size"] {
      guard case .number(.integer(let size)) = rawSize, size >= 0, size <= Int64(Int.max) else {
        throw malformed("An embedded-file Size is outside its supported range.")
      }
      declaredSize = Int(size)
    } else { declaredSize = nil }
    let checksum: Data?
    if let rawChecksum = parameters["CheckSum"] {
      guard case .string(let value) = rawChecksum, value.bytes.count == 16 else {
        throw malformed("An embedded-file CheckSum must contain a 16-byte MD5 digest.")
      }
      checksum = value.bytes
    } else { checksum = nil }
    return PDFEmbeddedFile(
      nameTreeKey: nameTreeKey,
      fileSpecification: specification,
      stream: stream,
      subtype: stream.dictionary.pdfName(named: "Subtype"),
      declaredSize: declaredSize,
      checksum: checksum,
      creationDate: try optionalDate(parameters["CreationDate"]),
      modificationDate: try optionalDate(parameters["ModDate"]),
      parameters: parameters,
      definingRevision: resolved.definitionRevision ?? revision
    )
  }

  private func collectionSchema(
    _ object: PDFObject?,
    revision: PDFRevisionIdentifier
  ) async throws -> [PDFName: PDFCollectionSchemaField] {
    guard let object else { return [:] }
    let dictionary = try await requiredDictionary(object, revision: revision, description: "Collection Schema")
    guard dictionary.count <= limits.maximumCollectionFields else {
      throw limit("A collection schema exceeds its configured field limit.")
    }
    var result = [PDFName: PDFCollectionSchemaField]()
    for (name, rawField) in dictionary {
      let field = try await requiredDictionary(rawField, revision: revision, description: "Collection field")
      guard let subtype = field.pdfName(named: "Subtype"),
        let display = try optionalString(field["N"], name: "N")
      else { throw malformed("A collection field requires Subtype and N entries.") }
      let orderValue = field.pdfInteger(named: "O") ?? 0
      guard orderValue >= Int64(Int.min), orderValue <= Int64(Int.max) else {
        throw malformed("A collection field order is outside its supported range.")
      }
      let isVisible: Bool = if case .boolean(let value)? = field["V"] { value } else { true }
      let isEditable: Bool = if case .boolean(let value)? = field["E"] { value } else { false }
      result[name] = .init(
        name: name,
        subtype: subtype,
        displayName: try PDFTextStringDecoder.decode(display, allowsUTF8: true),
        order: Int(orderValue),
        isVisible: isVisible,
        isEditable: isEditable,
        rawDictionary: field
      )
    }
    return result
  }

  private func collectionSort(
    _ object: PDFObject?,
    schema: [PDFName: PDFCollectionSchemaField],
    revision: PDFRevisionIdentifier
  ) async throws -> PDFCollectionSort? {
    guard let object else { return nil }
    let dictionary = try await requiredDictionary(object, revision: revision, description: "Collection Sort")
    let fields: [PDFName]
    switch dictionary["S"] {
    case .name(let value): fields = [value]
    case .array(let values):
      fields = try values.map {
        guard case .name(let name) = $0 else { throw malformed("Collection sort fields must be names.") }
        return name
      }
    default: throw malformed("A collection Sort dictionary requires S.")
    }
    guard fields.allSatisfy({ schema[$0] != nil }) else {
      throw malformed("A collection sort references an unknown schema field.")
    }
    let ascending: [Bool]
    switch dictionary["A"] {
    case nil: ascending = Array(repeating: true, count: fields.count)
    case .boolean(let value): ascending = Array(repeating: value, count: fields.count)
    case .array(let values):
      ascending = try values.map {
        guard case .boolean(let value) = $0 else { throw malformed("Collection sort directions must be Boolean.") }
        return value
      }
      guard ascending.count == fields.count else {
        throw malformed("Collection sort directions must match its fields.")
      }
    default: throw malformed("Collection sort direction has the wrong type.")
    }
    return .init(fields: fields, ascending: ascending)
  }

  private func collectionView(_ name: PDFName?) -> PDFCollectionView {
    switch name {
    case "D", nil: .details
    case "T": .tile
    case "H": .hidden
    case .some(let value): .unknown(value)
    }
  }

  private func optionalDate(_ object: PDFObject?) throws -> PDFDate? {
    guard let object else { return nil }
    guard case .string(let string) = object else {
      throw malformed("An embedded-file date must be a string.")
    }
    return try PDFDate(string)
  }

  private func resolvedDictionary(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    description: String
  ) async throws -> ([PDFName: PDFObject], PDFRevisionIdentifier) {
    if case .reference(let reference) = object {
      let resolved = try await resolver.resolve(reference, in: revision)
      guard case .value(.dictionary(let dictionary)) = resolved.value else {
        throw malformed("\(description) must identify an ordinary dictionary.")
      }
      return (dictionary, resolved.definitionRevision ?? revision)
    }
    guard case .dictionary(let dictionary) = object else {
      throw malformed("\(description) must be a dictionary.")
    }
    return (dictionary, revision)
  }

  private func requiredDictionary(
    _ object: PDFObject,
    revision: PDFRevisionIdentifier,
    description: String
  ) async throws -> [PDFName: PDFObject] {
    try await resolvedDictionary(object, revision: revision, description: description).0
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

  private func optionalString(_ object: PDFObject?, name: PDFName) throws -> PDFString? {
    guard let object else { return nil }
    guard case .string(let value) = object else { throw malformed("A file specification \(name) entry must be a string.") }
    return value
  }

  private static func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
  }

  private static func parseXMPDate(_ value: String) -> PDFDate? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let instant = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    guard let instant else { return nil }
    let output = DateFormatter()
    output.calendar = Calendar(identifier: .gregorian)
    output.locale = Locale(identifier: "en_US_POSIX")
    output.timeZone = TimeZone(secondsFromGMT: 0)
    output.dateFormat = "'D:'yyyyMMddHHmmss'Z'"
    return try? PDFDate(PDFString(output.string(from: instant)))
  }

  private func ensureOpen(_ revision: PDFRevisionIdentifier) throws {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard revisions.contains(where: { $0.identifier == revision }) else {
      throw PDFParsingError.unknownRevision(revision)
    }
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  private func limit(_ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: 0, message: message))
  }
}

private struct FileKey: Hashable {
  let revision: PDFRevisionIdentifier
  let reference: PDFObjectReference
}
