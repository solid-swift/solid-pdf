import Foundation
import SolidPostScript
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceRecordingCanonicalizerTests {
  @Test func distinguishesCoordinatesAndPaintWithEqualEffectShapes() {
    let first = recording(point: GraphicsPoint(x: 10, y: 20), paint: .deviceRGB(red: 1, green: 0, blue: 0))
    let moved = recording(point: GraphicsPoint(x: 11, y: 20), paint: .deviceRGB(red: 1, green: 0, blue: 0))
    let recolored = recording(point: GraphicsPoint(x: 10, y: 20), paint: .deviceRGB(red: 0, green: 0, blue: 1))

    let firstDigest = ConformanceRecordingCanonicalizer.digest(first)

    #expect(firstDigest == ConformanceRecordingCanonicalizer.digest(first))
    #expect(firstDigest != ConformanceRecordingCanonicalizer.digest(moved))
    #expect(firstDigest != ConformanceRecordingCanonicalizer.digest(recolored))
  }

  @Test func opaqueResourceIdentifiersAreCanonicalizedByFirstUse() {
    let first = formRecording(identifier: .init(rawValue: "runtime-a"))
    let second = formRecording(identifier: .init(rawValue: "runtime-b"))
    let stable = formRecording(identifier: .init(
      rawValue: "runtime-c",
      stableKey: GraphicsResourceStableKey(namespace: "XUID", value: Data([1]))
    ))

    #expect(ConformanceRecordingCanonicalizer.digest(first) == ConformanceRecordingCanonicalizer.digest(second))
    #expect(ConformanceRecordingCanonicalizer.digest(first) != ConformanceRecordingCanonicalizer.digest(stable))
  }

  private func recording(point: GraphicsPoint, paint: GraphicsPaint) -> GraphicsRecording {
    let path = GraphicsPath(elements: [.move(to: .init(x: 0, y: 0)), .line(to: point), .close])
    let state = GraphicsStateSnapshot(
      matrix: .identity,
      path: path,
      clip: GraphicsClip(imageableBounds: GraphicsRect(x: 0, y: 0, width: 100, height: 100)),
      paint: paint,
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
    let effect = GraphicsEffect.fill(path: path, rule: .winding, state: state)
    return GraphicsRecording(pages: [RecordedGraphicsPage(deviceDescriptor: .letter, effects: [effect])])
  }

  private func formRecording(identifier: GraphicsResourceIdentifier) -> GraphicsRecording {
    let state = GraphicsStateSnapshot(
      matrix: .identity,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: GraphicsDeviceDescriptor.letter.imageableBounds),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
    let form = GraphicsForm(
      bounds: GraphicsRect(x: 0, y: 0, width: 10, height: 10),
      matrix: .identity,
      deviceDescriptor: .letter,
      compilationState: state,
      displayList: GraphicsDisplayList(effects: [], resourceIdentifier: identifier),
      resourceIdentifier: identifier
    )
    return GraphicsRecording(pages: [RecordedGraphicsPage(
      deviceDescriptor: .letter,
      effects: [.form(form, state: state)]
    )])
  }
}
