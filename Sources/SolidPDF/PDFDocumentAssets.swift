import Foundation

actor PDFDocumentAssets<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let structure: PDFDocumentStructure<Session>
  private let revisions: [PDFDocumentRevision]
  private let limits: PDFParsingLimits
  private var metadataCache = [PDFRevisionIdentifier: PDFMetadata]()
  private var fileSpecificationCache = [FileKey: PDFFileSpecification]()
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
