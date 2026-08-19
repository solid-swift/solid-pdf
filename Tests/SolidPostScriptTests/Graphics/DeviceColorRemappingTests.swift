import SolidColor
import Testing

@testable import SolidPostScript

@Suite
struct DeviceColorRemappingTests {
  @Test func useCIEColorRemapsPaintWithoutChangingLanguageVisibleColor() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      .2 .4 .6 setrgbcolor
      currentpagedevice /UseCIEColor get
      currentcolorspace 0 get /DeviceRGB eq
      currentcolor currentrgbcolor
      0 0 1 1 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let values = try await result.context.results()
    let numbers = try values.prefix(6).map { try $0.value(as: RealValue.self).value }.reversed()
    #expect(zip(numbers, [0.2, 0.4, 0.6, 0.2, 0.4, 0.6]).allSatisfy { abs($0 - $1) < 1e-12 })
    #expect(try values[6].value(as: BooleanValue.self).value)
    #expect(try values[7].value(as: BooleanValue.self).value)

    let fill = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsStateSnapshot? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state
    }.first)
    guard case .color(.cie(let space, let source, let xyz, _)) = fill.paint else {
      Issue.record("Expected a CIE-remapped DeviceRGB paint")
      return
    }
    #expect(space == .cieBasedABC(whitePoint: .init(x: 1, y: 1, z: 1)))
    #expect(source == [0.2, 0.4, 0.6])
    #expect(xyz == ColorXYZ(x: 0.2, y: 0.4, z: 0.6))
    #expect(fill.colorSpace == .deviceRGB)
    #expect(fill.colorComponents == [0.2, 0.4, 0.6])
    #expect(fill.device.usesCIEColor)
  }

  @Test func missingDefaultColorSpaceIsUndefinedFromTriggeringOperator() async throws {
    let values = try await Interpreter.results(content: """
      { << /UseCIEColor true >> setpagedevice } stopped
      $error /errorname get
      $error /command get /setpagedevice load eq
      """)

    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: NameValue.self).value == "undefined")
    #expect(try values[2].value(as: BooleanValue.self).value)
  }

  @Test func defaultColorSpaceMustMatchTheDeviceFamily() async throws {
    let values = try await Interpreter.results(content: """
      /DefaultRGB [/CIEBasedA << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      { << /UseCIEColor true >> setpagedevice } stopped
      $error /errorname get
      """)

    #expect(try values[0].value(as: NameValue.self).value == "rangecheck")
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func identityDefaultDoesNotRecursivelyRemap() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/DeviceRGB] /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      .2 .4 .6 setrgbcolor 0 0 1 1 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let fill = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsStateSnapshot? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state
    }.first)
    let components = fill.paint.rgbComponents
    #expect(components.red == 0.2)
    #expect(components.green == 0.4)
    #expect(components.blue == 0.6)
    #expect(fill.colorSpace == .deviceRGB)
  }

  @Test func selectedDefaultIsFrozenButConvenienceSetterSelectsAgain() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      /DeviceRGB setcolorspace
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1]
        /MatrixABC [0 0 0 0 0 0 0 0 0] >>]
        /ColorSpace defineresource pop
      .2 .4 .6 setcolor 0 0 1 1 rectfill
      .2 .4 .6 setrgbcolor 2 0 1 1 rectfill
      showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let fills = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsStateSnapshot? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state
    })
    #expect(fills.count == 2)
    let first = fills[0].paint.rgbComponents
    let second = fills[1].paint.rgbComponents
    #expect(first.red != 0 || first.green != 0 || first.blue != 0)
    #expect(second.red == 0)
    #expect(second.green == 0)
    #expect(second.blue == 0)
  }
}
