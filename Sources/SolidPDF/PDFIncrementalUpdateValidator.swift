import Foundation

enum PDFIncrementalUpdateValidator {
  static func validate(
    _ data: Data,
    expectedRevisionCount: Int,
    securityContext: PDFSecurityContext?,
    limits updateLimits: PDFIncrementalWritingLimits
  ) async throws -> Int {
    var parsingLimits = PDFParsingLimits()
    parsingLimits.maximumInputBytes = updateLimits.maximumStagedDocumentBytes
    parsingLimits.maximumAuthenticityScratchBytes = updateLimits.maximumValidationScratchBytes
    let options = PDFParsingOptions(limits: parsingLimits)
    let session = try await PDFDataInputSource(data).makeSession()
    do {
      let reader = try await PDFSourceReader(session: session, options: options)
      let index = try await PDFCrossReferenceParser(reader: reader, options: options).parse()
      guard index.revisions.count == expectedRevisionCount else {
        throw PDFIncrementalUpdateError.validationFailed
      }
      let resolver = PDFDocumentResolver(
        reader: reader,
        index: index,
        options: options,
        externalStreamProvider: nil,
        securityContext: securityContext,
        openedSourceLength: Int64(data.count)
      )
      let structure = PDFDocumentStructure(
        resolver: resolver,
        revisions: index.revisions,
        headerVersion: index.version,
        limits: parsingLimits
      )
      let assets = PDFDocumentAssets(
        resolver: resolver,
        structure: structure,
        revisions: index.revisions,
        limits: parsingLimits
      )
      let interactive = PDFDocumentInteractiveStructure(
        resolver: resolver,
        structure: structure,
        assets: assets,
        revisions: index.revisions,
        limits: parsingLimits
      )
      do {
        _ = try await structure.catalog(in: index.latestRevision.identifier)
        try await interactive.validateAcroForm(in: index.latestRevision.identifier)
        let pageCount = try await structure.pageCount(in: index.latestRevision.identifier)
        await interactive.close()
        await assets.close()
        await structure.close()
        await resolver.close()
        return pageCount
      } catch {
        await interactive.close()
        await assets.close()
        await structure.close()
        await resolver.close()
        throw error
      }
    } catch {
      await session.close()
      throw error
    }
  }
}
