import Foundation

enum PDFStructuralStreamDecoder {
  static func decode(
    _ data: Data,
    dictionary: [PDFName: PDFObject],
    limits: PDFParsingLimits,
    offset: Int64
  ) async throws -> Data {
    let stream = PDFStreamObject(
      dictionary: dictionary,
      encodedRange: PDFSourceRange(uncheckedOffset: offset, length: data.count)
    )
    let options = PDFParsingOptions(limits: limits)
    let configuration = try await PDFStreamConfiguration.resolve(
      stream: stream,
      options: options,
      resolve: { reference in throw PDFParsingError.unresolvedReference(reference) }
    )
    guard configuration.fileSpecification == nil else {
      throw PDFParsingError.unsupported(
        .externalStream,
        .init(offset: offset, message: "A structural stream cannot use external data.")
      )
    }
    let session = try await PDFDataInputSource(data).makeSession()
    let input = try await PDFDecodedStreamInput(externalSession: session)
    let registry = PDFDecodedStreamRegistry()
    let state = try PDFIncrementalDecodedStreamState(
      input: input,
      filters: configuration.filters,
      options: options,
      diagnostic: .init(offset: offset, message: "The structural stream is malformed."),
      registry: registry
    )
    await state.register()
    let decoded = PDFDecodedStream(state: state)
    var result = Data()
    do {
      for try await chunk in decoded { result.append(chunk) }
      await decoded.close()
      return result
    } catch {
      await decoded.close()
      throw error
    }
  }
}
