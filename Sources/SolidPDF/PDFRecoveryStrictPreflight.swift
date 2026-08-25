enum PDFRecoveryStrictPreflight {
  static func validate<Session: PDFInputSourceSession>(
    index: PDFCrossReferenceIndex,
    reader: PDFSourceReader<Session>,
    limits: PDFParsingLimits
  ) async throws {
    for (objectNumber, entry) in index.entries.sorted(by: { $0.key < $1.key }) {
      try Task.checkCancellation()
      guard case .uncompressed(let offset, let generation) = entry else { continue }
      var parser = PDFObjectParser(reader: reader, position: offset, limits: limits)
      let header = try await parser.parseIndirectHeader()
      let expected = PDFObjectReference(
        uncheckedObjectNumber: objectNumber,
        generationNumber: generation
      )
      guard header.reference == expected else {
        throw PDFParsingError.malformed(
          .init(
            offset: offset,
            object: expected,
            message: "The cross-reference offset does not identify its declared object."
          )
        )
      }
      parser = PDFObjectParser(reader: reader, position: offset, limits: limits)
      do {
        let raw = try await parser.parseRawIndirectObject()
        guard raw.reference == expected else {
          throw PDFParsingError.malformed(
            .init(offset: offset, object: expected, message: "The indirect object header changed during validation.")
          )
        }
      } catch let error as PDFParsingError {
        if case .malformed(let diagnostic) = error,
          diagnostic.message == "A directly parseable stream requires a direct nonnegative Length."
        {
          continue
        }
        throw error
      }
    }
  }
}
