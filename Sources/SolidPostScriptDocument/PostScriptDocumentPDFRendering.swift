import Foundation
import SolidPDF
import SolidPostScript
import SolidPostScriptPDF

extension PostScriptDocument {
  /// Renders selected transmitted pages to a deterministic in-memory PDF document.
  public func renderPDF(
    options: PDFRenderOptions = .init(),
    documentOptions: PostScriptDocumentRenderOptions = .init(),
    environment: InterpreterEnvironment = .init()
  ) async throws -> GraphicsRenderResult<PDFEncodedDocument> {
    let options = configuredPDFOptions(options, documentOptions: documentOptions)
    let target = PDFDataGraphicsTarget(
      sink: PDFDataOutputSink(),
      options: options,
      deviceDescriptor: pdfDeviceDescriptor
    )
    let result: GraphicsRenderResult<PDFEncodedDocument>
    if let timeout = documentOptions.timeout {
      result = try await withThrowingTaskGroup(of: GraphicsRenderResult<PDFEncodedDocument>.self) { group in
        group.addTask { try await self.render(to: target, environment: environment) }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw PostScriptDocumentError.timeout
        }
        guard let first = try await group.next() else { throw PostScriptDocumentError.timeout }
        group.cancelAll()
        return first
      }
    } else {
      result = try await render(to: target, environment: environment)
    }
    guard result.output.pageCount > 0 else { throw PostScriptDocumentError.noPages }
    return result
  }

  /// Renders selected transmitted pages to an atomically published PDF file.
  public func renderPDF(
    to destination: URL,
    replacingExisting: Bool = false,
    options: PDFRenderOptions = .init(),
    documentOptions: PostScriptDocumentRenderOptions = .init(),
    environment: InterpreterEnvironment = .init()
  ) async throws -> GraphicsRenderResult<URL> {
    let options = configuredPDFOptions(options, documentOptions: documentOptions)
    let target = PDFFileGraphicsTarget(
      sink: PDFAtomicFileOutputSink(destination: destination, replacingExisting: replacingExisting),
      options: options,
      deviceDescriptor: pdfDeviceDescriptor
    )
    if let timeout = documentOptions.timeout {
      return try await withThrowingTaskGroup(of: GraphicsRenderResult<URL>.self) { group in
        group.addTask { try await self.render(to: target, environment: environment) }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw PostScriptDocumentError.timeout
        }
        guard let first = try await group.next() else { throw PostScriptDocumentError.timeout }
        group.cancelAll()
        return first
      }
    }
    return try await render(to: target, environment: environment)
  }

  private func configuredPDFOptions(
    _ supplied: PDFRenderOptions,
    documentOptions: PostScriptDocumentRenderOptions
  ) -> PDFRenderOptions {
    var result = supplied
    result.metadata.title = result.metadata.title ?? metadata.title
    result.metadata.creator = result.metadata.creator ?? metadata.creator
    if let version = metadata.version, result.metadata.producer == "SolidPDF" {
      result.metadata.producer = "SolidPDF; source \(version)"
    }
    if case .pages(let pages) = documentOptions.pages { result.selectedPageOrdinals = pages }
    let selectedPages = metadata.pages.enumerated().filter { documentOptions.pages.contains($0.offset + 1) }
    result.pageLabels = selectedPages.map(\.element.label)
    if documentOptions.cropMode != .media {
      result.cropBoxes = selectedPages.map { page in page.element.bounds.map(pdfCropBox) }
    }
    return result
  }

  private var pdfDeviceDescriptor: GraphicsDeviceDescriptor {
    guard metadata.kind == .encapsulatedPostScript, let bounds = metadata.bounds else { return .letter }
    let media = GraphicsRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    return GraphicsDeviceDescriptor(
      mediaBounds: media,
      imageableBounds: media,
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .init(a: 1, b: 0, c: 0, d: 1, tx: -bounds.lowerX, ty: -bounds.lowerY)
    )
  }

  private func pdfCropBox(_ bounds: PostScriptDocumentBounds) -> GraphicsRect {
    GraphicsRect(x: bounds.lowerX, y: bounds.lowerY, width: bounds.width, height: bounds.height)
  }
}
