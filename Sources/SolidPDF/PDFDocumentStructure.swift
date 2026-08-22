actor PDFDocumentStructure<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let revisions: [PDFDocumentRevision]
  private let headerVersion: PDFFileVersion
  private let limits: PDFParsingLimits
  private var catalogs = [PDFRevisionIdentifier: PDFDocumentCatalog]()
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
    catalogs.removeAll()
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
