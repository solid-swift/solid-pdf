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
      /DefaultRGB /ColorSpace resourcestatus {
        pop pop /DefaultRGB /ColorSpace undefineresource
      } if
      { << /UseCIEColor true >> setpagedevice } stopped clear
      $error /errorname get
      $error /command get /setpagedevice load eq
      currentpagedevice /UseCIEColor get
      """)

    let remainsDisabled = try values[0].value(as: BooleanValue.self).value
    #expect(!remainsDisabled)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[2].value(as: NameValue.self).value == "undefined")
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

  @Test func sampledImageUsesTheFrozenSelectionAndRetainsItsSourceSpace() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1]
        /MatrixABC [0 0 0 0 0 0 0 0 0] >>]
        /ColorSpace defineresource pop
      << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
         /ImageMatrix [1 0 0 1 0 0] /Decode [0 1 0 1 0 1]
         /DataSource <ff0000> >> image showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let image = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsImage? in
      guard case .image(let image, _) = effect else { return nil }
      return image
    }.first)
    #expect(image.descriptor.sourceColorSpace == .deviceRGB)
    #expect(image.sourceComponents == [1, 0, 0])
    #expect(image.components.count == 3)
    #expect(image.components[0] > 0.9)
    #expect(image.components[1] < 0.01)
    #expect(image.components.reduce(0, +) > 1)
  }

  @Test func shadingSelectsAndRetainsItsOwnDeviceColorRoute() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 10 0]
         /Function << /FunctionType 2 /Domain [0 1]
                      /C0 [1 0 0] /C1 [0 0 1] /N 1 >>
      >> shfill
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1]
        /MatrixABC [0 0 0 0 0 0 0 0 0] >>]
        /ColorSpace defineresource pop
      showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let shading = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsShading? in
      guard case .shading(let shading, _) = effect else { return nil }
      return shading
    }.first)
    #expect(shading.colorSpace == .deviceRGB)
    guard case .color(.cie(let space, _, _, _)) = try #require(shading.mesh.triangles.first).first.paint else {
      Issue.record("Expected a CIE-resolved shading vertex")
      return
    }
    #expect(space == .cieBasedABC(whitePoint: .init(x: 1, y: 1, z: 1)))
  }

  @Test func uncoloredPatternPreservesItsSelectedUnderlyingRoute() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      /p << /PatternType 1 /PaintType 2 /TilingType 1
        /BBox [0 0 2 2] /XStep 2 /YStep 2
        /PaintProc { pop 0 0 2 2 rectfill }
      >> matrix makepattern def
      [/Pattern /DeviceRGB] setcolorspace
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1]
        /MatrixABC [0 0 0 0 0 0 0 0 0] >>]
        /ColorSpace defineresource pop
      1 0 0 p setcolor 0 0 4 4 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let state = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsStateSnapshot? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state
    }.first)
    guard case .pattern(.tiling(_, let underlying)) = state.paint,
      case .color(.cie(_, _, let xyz, _)) = try #require(underlying)
    else {
      Issue.record("Expected a CIE-resolved uncolored pattern")
      return
    }
    #expect(xyz.x == 1)
    #expect(xyz.y == 0)
    #expect(xyz.z == 0)
  }

  @Test func grayAndCMYKDefaultsUseTheirPermittedCIESpaces() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/DeviceRGB] /ColorSpace defineresource pop
      /DefaultGray [/CIEBasedA << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      /DefaultCMYK [/CIEBasedDEFG << /WhitePoint [1 1 1]
        /Table [2 2 2 2
          [[<000000000000000000000000> <000000000000000000000000>]
           [<000000000000000000000000> <000000000000000000000000>]]]
      >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      .5 setgray 0 0 1 1 rectfill
      .1 .2 .3 .4 setcmykcolor 2 0 1 1 rectfill
      showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let fills = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsPaint? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state.paint
    })
    guard case .color(.cie(let graySpace, _, _, _)) = fills[0],
      case .color(.cie(let cmykSpace, _, _, _)) = fills[1]
    else {
      Issue.record("Expected CIE-remapped gray and CMYK paints")
      return
    }
    #expect(graySpace == .cieBasedA(whitePoint: .init(x: 1, y: 1, z: 1)))
    #expect(cmykSpace == .cieBasedDEFG(whitePoint: .init(x: 1, y: 1, z: 1)))
  }

  @Test func compositeSpacesRecursivelyUseFrozenDefaultRoutes() async throws {
    let result = try await Interpreter.render(
      content: """
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1] >>]
        /ColorSpace defineresource pop
      << /UseCIEColor true >> setpagedevice
      [/Indexed /DeviceRGB 0 <ff0000>] setcolorspace
      0 setcolor 0 0 1 1 rectfill
      [/Separation /Missing /DeviceRGB { dup 1 exch sub 0 }] setcolorspace
      .25 setcolor 2 0 1 1 rectfill
      [/DeviceN [/First /Second] /DeviceRGB { pop pop 1 0 0 }] setcolorspace
      .5 .5 setcolor 4 0 1 1 rectfill
      showpage
      """,
      to: RecordingGraphicsTarget()
    )

    let fills = try #require(result.output.pages.first?.effects.compactMap { effect -> GraphicsStateSnapshot? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state
    })
    #expect(fills.count == 3)
    #expect(fills[0].colorSpace == .indexed(base: .deviceRGB, maximumIndex: 0))
    guard case .color(.cie(_, _, _, _)) = fills[0].paint,
      case .color(.named(_, _, _, .cie(_, _, _, _))) = fills[1].paint,
      case .color(.named(_, _, _, .cie(_, _, _, _))) = fills[2].paint
    else {
      Issue.record("Expected recursively remapped Indexed, Separation, and DeviceN paints")
      return
    }
  }

  @Test func sharedDefaultsDoNotSharePerContextDeviceSelection() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: """
      true setglobal
      /DefaultRGB [/CIEBasedABC << /WhitePoint [1 1 1]
        /MatrixABC [0 0 0 0 0 0 0 0 0] >>]
        /ColorSpace defineresource pop
      false setglobal
      """,
      environment: environment
    )

    async let remapped = Interpreter.render(
      content: "<< /UseCIEColor true >> setpagedevice 1 0 0 setrgbcolor 0 0 1 1 rectfill showpage",
      to: RecordingGraphicsTarget(),
      environment: environment
    )
    async let direct = Interpreter.render(
      content: "1 0 0 setrgbcolor 0 0 1 1 rectfill showpage",
      to: RecordingGraphicsTarget(),
      environment: environment
    )
    let (remappedResult, directResult) = try await (remapped, direct)

    let remappedPaint = try recordedFillPaint(remappedResult.output)
    let directPaint = try recordedFillPaint(directResult.output)
    guard case .color(.cie) = remappedPaint, case .deviceRGB = directPaint else {
      Issue.record("Expected independent remapped and direct device selections")
      return
    }
  }

  private func recordedFillPaint(_ recording: GraphicsRecording) throws -> GraphicsPaint {
    try #require(recording.pages.first?.effects.compactMap { effect -> GraphicsPaint? in
      guard case .fillRectangles(_, let state) = effect else { return nil }
      return state.paint
    }.first)
  }
}
