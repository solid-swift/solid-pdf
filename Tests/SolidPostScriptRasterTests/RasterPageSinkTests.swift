import SolidPostScript
import SolidPostScriptRaster
import Testing

@Suite
struct RasterPageSinkTests {
  private struct CollectingSink: RasterPageSink {
    final class Session: RasterPageSinkSession {
      var pages: [RasterRenderedPage] = []

      func consume(_ page: RasterRenderedPage) { pages.append(page) }
      func finish() -> sending [RasterRenderedPage] { pages }
      func abort() { pages.removeAll() }
    }

    func makeSession() -> sending Session { Session() }
  }

  @Test
  func streamsCopiesInTransmissionOrder() async throws {
    let target = RasterPageSinkTarget(
      pixelWidth: 16,
      pixelHeight: 12,
      sink: CollectingSink()
    )
    let result = try await Interpreter.render(
      content: "<< /NumCopies 2 >> setpagedevice 0 0 4 4 rectfill showpage",
      to: target
    )
    #expect(result.output.count == 2)
    #expect(result.output.map(\.transmissionOrdinal) == [1, 1])
    #expect(result.output.map(\.copyOrdinal) == [1, 2])
    #expect(result.output.allSatisfy { $0.image.width == 16 && $0.image.height == 12 })
  }
}
