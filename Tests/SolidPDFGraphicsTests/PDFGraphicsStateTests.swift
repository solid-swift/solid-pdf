import Foundation
import SolidPDF
@testable import SolidPDFGraphics
import SolidPostScript
import Testing

@Suite
struct PDFGraphicsStateTests {
  @Test
  func emitsOpaqueFillAndStrokeWithSeparatePaintAndTransformedPath() async throws {
    let content = "q 2 0 0 2 0 0 cm 1 0 0 RG 0 1 0 rg 2 w 0 0 m 10 0 l 10 10 l h B Q"
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(content: content)))
    let page = try await document.page(at: 0)
    var events: [GraphicsEvent] = []
    let handler = PDFGraphicsInstructionHandler(
      device: .letter,
      resources: PDFGraphicsResourceResolver(
        document: document,
        revision: document.latestRevision.identifier,
        resources: page.resources.value,
        limits: .init()
      ),
      limits: .init(),
      emit: { events.append($0) }
    )
    try await executor(document: document, page: page, handler: handler).execute()

    let paints = events.compactMap { event -> GraphicsOperation.Paint? in
      guard case .paint(let paint) = event.operation else { return nil }
      return paint
    }
    #expect(paints.count == 2)
    let fill = events.first { if case .paint(.fill) = $0.operation { true } else { false } }
    let stroke = events.first { if case .paint(.stroke) = $0.operation { true } else { false } }
    #expect(fill?.before.paint == .deviceRGB(red: 0, green: 1, blue: 0))
    #expect(stroke?.before.paint == .deviceRGB(red: 1, green: 0, blue: 0))
    #expect(fill?.before.path.elements.contains(.line(to: GraphicsPoint(x: 20, y: 20))) == true)
    #expect(fill?.origin?.byteSegments.isEmpty == false)
    await document.close()
  }

  @Test
  func resolvesCalculatorSeparationAndIdentityExtendedState() async throws {
    let content = "/Spot cs 0.25 scn /Opaque gs 0 0 10 10 re f"
    let resources = """
      << /ColorSpace << /Spot [/Separation /Brand /DeviceGray 5 0 R] >>
         /ExtGState << /Opaque << /BM /Normal /ca 1 /CA 1 /OPM 0 /OP true /op false >> >> >>
      """
    let function = "<< /FunctionType 4 /Domain [0 1] /Range [0 1] /Length 3 >>\nstream\n{ }\nendstream"
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(content: content, resources: resources, extraObjects: [function]))
    )
    let page = try await document.page(at: 0)
    var events: [GraphicsEvent] = []
    let handler = PDFGraphicsInstructionHandler(
      device: .letter,
      resources: PDFGraphicsResourceResolver(
        document: document,
        revision: document.latestRevision.identifier,
        resources: page.resources.value,
        limits: .init()
      ),
      limits: .init(),
      emit: { events.append($0) }
    )
    try await executor(document: document, page: page, handler: handler).execute()

    let fill = events.first { if case .paint(.fill) = $0.operation { true } else { false } }
    guard case .color(.named(_, let colorants, let tints, let alternative))? = fill?.before.paint else {
      Issue.record("Expected a named-color paint")
      await document.close()
      return
    }
    #expect(colorants == ["Brand"])
    #expect(tints == [0.25])
    #expect(alternative == .deviceGray(0.25))
    #expect(fill?.before.nonstrokingOverprintForTest == false)
    await document.close()
  }

  @Test
  func rejectsNonidentityTransparencyBeforePainting() async throws {
    let content = "/Transparent gs 0 0 10 10 re f"
    let resources = "<< /ExtGState << /Transparent << /ca 0.5 >> >> >>"
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(content: content, resources: resources))
    )
    let page = try await document.page(at: 0)
    let handler = PDFGraphicsInstructionHandler(
      device: .letter,
      resources: PDFGraphicsResourceResolver(
        document: document,
        revision: document.latestRevision.identifier,
        resources: page.resources.value,
        limits: .init()
      ),
      limits: .init(),
      emit: { _ in }
    )
    await #expect(throws: PDFGraphicsError.self) {
      try await executor(document: document, page: page, handler: handler).execute()
    }
    await document.close()
  }

  @Test
  func resolvesTypeOneAndPerColorantHalftones() async throws {
    let typeOne = "<< /HalftoneType 1 /Frequency 20 /Angle 15 /SpotFunction /Round /TransferFunction /Identity >>"
    let resources = """
      << /ExtGState
         << /Screen << /HT \(typeOne) /HTP [3 4] >>
            /ColorScreens
              << /HT
                << /HalftoneType 5
                   /Default \(typeOne)
                   /Red << /HalftoneType 1 /Frequency 25 /Angle 45 /SpotFunction /Line >>
                >>
              >>
         >>
      >>
      """
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(content: "/Screen gs /ColorScreens gs", resources: resources))
    )
    let page = try await document.page(at: 0)
    let handler = PDFGraphicsInstructionHandler(
      device: .letter,
      resources: PDFGraphicsResourceResolver(
        document: document,
        revision: document.latestRevision.identifier,
        resources: page.resources.value,
        limits: .init()
      ),
      limits: .init(),
      emit: { _ in }
    )
    try await executor(document: document, page: page, handler: handler).execute()

    guard case .colorants(let screens) = handler.currentSnapshot.deviceRendering.halftone else {
      Issue.record("Expected a per-colorant PDF halftone")
      await document.close()
      return
    }
    #expect(screens["Default"] != nil)
    #expect(screens["Red"] != nil)
    #expect(handler.currentSnapshot.deviceRendering.halftonePhase == GraphicsPoint(x: 3, y: 4))
    await document.close()
  }

  @Test(arguments: [6, 10, 16])
  func resolvesThresholdHalftones(type: Int) async throws {
    let definition: String
    let bytes: String
    switch type {
    case 6:
      definition = "/HalftoneType 6 /Width 2 /Height 2"
      bytes = "\u{01}\u{02}\u{03}\u{04}"
    case 10:
      definition = "/HalftoneType 10 /Xsquare 1 /Ysquare 1"
      bytes = "\u{01}\u{02}"
    default:
      definition = "/HalftoneType 16 /Width 2 /Height 1"
      bytes = "\u{00}\u{01}\u{00}\u{02}"
    }
    let stream = "<< \(definition) /Length \(bytes.utf8.count) >>\nstream\n\(bytes)\nendstream"
    let resources = "<< /ExtGState << /Screen << /HT 5 0 R >> >> >>"
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(
      content: "/Screen gs",
      resources: resources,
      extraObjects: [stream]
    )))
    let page = try await document.page(at: 0)
    let handler = PDFGraphicsInstructionHandler(
      device: .letter,
      resources: PDFGraphicsResourceResolver(
        document: document,
        revision: document.latestRevision.identifier,
        resources: page.resources.value,
        limits: .init()
      ),
      limits: .init(),
      emit: { _ in }
    )
    try await executor(document: document, page: page, handler: handler).execute()

    guard case .threshold(let screen) = handler.currentSnapshot.deviceRendering.halftone else {
      Issue.record("Expected a threshold PDF halftone")
      await document.close()
      return
    }
    #expect(screen.bitsPerSample == (type == 16 ? 16 : 8))
    #expect(screen.usesAngledSquares == (type == 10))
    await document.close()
  }

  private func executor(
    document: PDFDocument<PDFDataInputSource>,
    page: PDFPage,
    handler: PDFGraphicsInstructionHandler<PDFDataInputSource>
  ) -> PDFContentExecutor {
    PDFContentExecutor(
      parser: PDFContentParser(
        input: PDFContentInput(
          streams: page.contentStreams,
          open: { try await document.decodedStream(of: $0) }
        ),
        revision: document.latestRevision.identifier,
        page: page,
        maximumScratchBytes: 1_024 * 1_024
      ),
      handler: handler,
      maximumOperators: 1_000
    )
  }

  private func fixture(
    content: String,
    resources: String = "<< >>",
    extraObjects: [String] = []
  ) -> Data {
    var objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources \(resources) /Contents 4 0 R >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ]
    objects.append(contentsOf: extraObjects)
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}

private extension GraphicsStateSnapshot {
  var nonstrokingOverprintForTest: Bool { overprint }
}
