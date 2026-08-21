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
}
