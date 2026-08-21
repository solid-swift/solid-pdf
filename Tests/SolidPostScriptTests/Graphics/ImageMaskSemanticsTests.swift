import Testing

@testable import SolidPostScript

@Suite
struct ImageMaskSemanticsTests {
  @Test func sampleInterleavedExplicitMasksPrecedeColorComponents() async throws {
    let image = try await recordedImage(
      """
      << /ImageType 3 /InterleaveType 1
         /DataDict << /ImageType 1 /Width 2 /Height 1 /BitsPerComponent 8
           /ImageMatrix [2 0 0 1 0 0] /Decode [0 1] /DataSource <00ff0100> >>
         /MaskDict << /ImageType 1 /Width 2 /Height 1 /BitsPerComponent 8
           /ImageMatrix [2 0 0 1 0 0] /Decode [0 1] >>
      >> image showpage
      """
    )

    #expect(image.components == [1, 0])
    #expect(image.mask?.opacities == [1, 0])
    #expect(image.descriptor.mask == .explicit(
      width: 2,
      height: 1,
      maskToDevice: GraphicsMatrix(a: 0.5, b: 0, c: 0, d: 1, tx: 0, ty: 0),
      interpolate: false
    ))
  }

  @Test func rowInterleavedMasksHonorIndependentRowPaddingAndHeightRatio() async throws {
    let image = try await recordedImage(
      """
      << /ImageType 3 /InterleaveType 2
         /DataDict << /ImageType 1 /Width 2 /Height 2 /BitsPerComponent 8
           /ImageMatrix [2 0 0 2 0 0] /Decode [0 1] /DataSource <80ff0000ff> >>
         /MaskDict << /ImageType 1 /Width 2 /Height 1 /BitsPerComponent 1
           /ImageMatrix [2 0 0 1 0 0] /Decode [0 1] >>
      >> image showpage
      """
    )

    #expect(image.components == [1, 0, 0, 1])
    #expect(image.mask?.opacities == [0, 1])
  }

  @Test func separateExplicitMasksMayUseIndependentResolution() async throws {
    let image = try await recordedImage(
      """
      << /ImageType 3 /InterleaveType 3
         /DataDict << /ImageType 1 /Width 2 /Height 2 /BitsPerComponent 8
           /ImageMatrix [2 0 0 2 0 0] /Decode [0 1] /DataSource <ff0000ff> >>
         /MaskDict << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 1
           /ImageMatrix [1 0 0 1 0 0] /Decode [0 1] /DataSource <00> >>
      >> image showpage
      """
    )

    #expect(image.components == [1, 0, 0, 1])
    #expect(image.mask?.opacities == [1])
  }

  @Test func colorKeyRangesCompareRawSamplesBeforeDecode() async throws {
    let image = try await recordedImage(
      """
      << /ImageType 4 /Width 3 /Height 1 /BitsPerComponent 8
         /ImageMatrix [3 0 0 1 0 0] /Decode [1 0]
         /MaskColor [0 127] /DataSource <0080ff>
      >> image showpage
      """
    )

    #expect(image.components == [1, Float(127.0 / 255.0), 0])
    #expect(image.mask?.opacities == [0, 1, 1])
    #expect(image.descriptor.mask == .colorKey(ranges: [
      GraphicsImageSampleRange(lowerBound: 0, upperBound: 127),
    ]))
  }

  @Test func malformedMasksUseImageErrorLifecycle() async throws {
    let values = try await Interpreter.results(
      content: """
      { << /ImageType 3 /InterleaveType 3
           /DataDict << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
             /ImageMatrix [1 0 0 1 0 0] /Decode [0 1] /DataSource <00> >>
           /MaskDict << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 1
             /ImageMatrix [1 0 0 1 1 0] /Decode [0 1] /DataSource <00> >>
        >> image } stopped
      $error /errorname get $error /command get /image load eq
      """
    )
    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: NameValue.self).value == "typecheck")
    #expect(try values[2].value(as: BooleanValue.self).value)
  }

  @Test func imageTypeResourcesAdvertiseOnlyImplementedTypes() async throws {
    let values: [IntegerValue] = try await Interpreter.result(
      content: "1 /ImageType findresource 3 /ImageType findresource 4 /ImageType findresource",
      count: 3
    )
    #expect(values.map(\.value) == [4, 3, 1])
  }

  @Test func consumersWithoutMaskSupportFailInsteadOfDroppingMaskData() async {
    await #expect(throws: Error.ioError) {
      try await Interpreter.render(
        content: """
        << /ImageType 4 /Width 1 /Height 1 /BitsPerComponent 8
           /ImageMatrix [1 0 0 1 0 0] /Decode [0 1]
           /MaskColor [0] /DataSource <ff>
        >> image
        """,
        to: EventOnlyImageTarget()
      )
    }
  }

  private func recordedImage(_ content: String) async throws -> GraphicsImage {
    let result = try await Interpreter.render(content: content, to: RecordingGraphicsTarget())
    guard case .image(let image, _) = try #require(result.output.pages.first?.effects.first) else {
      Issue.record("Expected an image effect")
      throw Error.ioError
    }
    return image
  }
}

private struct EventOnlyImageTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = Void

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = Void

    var pages: [Void] { [] }

    func process(_ event: GraphicsEvent) {}
    func finish() -> sending Void {}
    func abort() {}
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}
