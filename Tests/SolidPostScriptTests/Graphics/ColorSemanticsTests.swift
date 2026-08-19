import SolidColor
import Testing

@testable import SolidPostScript

@Suite
struct ColorSemanticsTests {

  @Test func deviceColorSpacesEstablishTheirSpecifiedInitialValues() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      /DeviceGray setcolorspace currentcolor
      /DeviceRGB setcolorspace currentcolor
      /DeviceCMYK setcolorspace currentcolor
      """,
      count: 8
    )

    #expect(values.map(\.value).reversed() == [0, 0, 0, 0, 0, 0, 0, 1])
  }

  @Test func cieBasedAExecutesDecodeAndUsesPostScriptMatrixOrdering() async throws {
    let result = try await Interpreter.render(
      content: """
      [/CIEBasedA <<
        /RangeA [0 2]
        /DecodeA {2 mul}
        /MatrixA [.25 .5 .75]
        /RangeLMN [0 2 0 2 0 2]
        /WhitePoint [1 1 1]
      >>] setcolorspace
      .5 setcolor
      0 0 moveto 10 0 lineto 10 10 lineto closepath fill showpage
      currentrgbcolor
      """,
      to: RecordingGraphicsTarget()
    )

    guard case .fill(_, _, let state) = try #require(result.output.pages.first?.effects.first),
      case .color(.cie(_, let source, let xyz, _)) = state.paint
    else {
      Issue.record("Expected a resolved CIE paint")
      return
    }
    #expect(source == [0.5])
    #expect(xyz == ColorXYZ(x: 0.25, y: 0.5, z: 0.75))
    let values = try await result.context.results()
    #expect(try values.map { try $0.value(as: RealValue.self).value }.reversed() == [0, 0, 0])
  }

  @Test func indexedAndNamedSpacesResolveWithoutLosingSemanticIntent() async throws {
    let indexed = try await Interpreter.render(
      content: """
      [/Indexed /DeviceRGB 1 <ff000000ff00>] setcolorspace 1 setcolor
      0 0 1 1 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    guard case .fillRectangles(_, let indexedState) = try #require(indexed.output.pages.first?.effects.first)
    else {
      Issue.record("Expected an indexed fill")
      return
    }
    #expect(indexedState.paint.rgbComponents.green == 1)

    let named = try await Interpreter.render(
      content: """
      [/Separation /Spot /DeviceRGB {dup 1 exch sub 0}] setcolorspace .25 setcolor
      0 0 1 1 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    guard case .fillRectangles(_, let namedState) = try #require(named.output.pages.first?.effects.first),
      case .color(.named(_, let colorants, let tints, let alternative)) = namedState.paint
    else {
      Issue.record("Expected a named-color fill")
      return
    }
    #expect(colorants == ["Spot"])
    #expect(tints == [0.25])
    #expect(alternative.rgb == ColorRGB(red: 0.25, green: 0.75, blue: 0))
  }

  @Test func deviceNTransformsAllTintsAndParticipatesInGraphicsSave() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      [/DeviceN [/Orange /Green] /DeviceRGB {0}] setcolorspace
      .2 .8 setcolor gsave .9 .1 setcolor grestore currentcolor
      save .4 .6 setcolor restore currentcolor
      """,
      count: 4
    )
    #expect(values.map(\.value).reversed() == [0.2, 0.8, 0.2, 0.8])
  }

  @Test func colorRenderingAndOverprintAreRestorableGraphicsState() async throws {
    let values = try await Interpreter.results(
      content: """
      /crd << /ColorRenderingType 1 /WhitePoint [1 1 1]
        /TransformPQR [{} {} {}]
      >> def
      crd setcolorrendering true setoverprint
      gsave false setoverprint grestore currentoverprint
      currentcolorrendering crd eq
      """
    )
    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func transferAndColorAdjustmentProceduresAreCompiledAndRestored() async throws {
    let values = try await Interpreter.results(content: """
      /invert {1 exch sub} def
      /invert load settransfer
      currenttransfer /invert load eq
      gsave {} settransfer grestore currenttransfer /invert load eq
      save {} settransfer restore currenttransfer /invert load eq
      {} setblackgeneration
      {.1 add} setundercolorremoval
      .2 .4 .6 setrgbcolor currentcmykcolor
      """)

    let numbers = try values.prefix(4).map { try $0.value(as: RealValue.self).value }.reversed()
    #expect(zip(numbers, [0.3, 0.1, 0, 0.4]).allSatisfy { abs($0 - $1) < 1e-9 })
    #expect(try values[4].value(as: BooleanValue.self).value)
    #expect(try values[5].value(as: BooleanValue.self).value)
    #expect(try values[6].value(as: BooleanValue.self).value)
  }

  @Test func transferProcedureRequiresBalancedSingleNumericResult() async throws {
    let values = try await Interpreter.results(content: """
      {{dup} settransfer} stopped
      $error /errorname get
      """)

    #expect(try values[0].value(as: NameValue.self).value == "typecheck")
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func typeOneColorRenderingTransformsCIEValuesIntoDeviceColor() async throws {
    let result = try await Interpreter.render(
      content: """
      << /ColorRenderingType 1 /WhitePoint [.9 1 1]
         /TransformPQR [
           {.5 mul exch pop exch pop exch pop exch pop}
           {.5 mul exch pop exch pop exch pop exch pop}
           {.5 mul exch pop exch pop exch pop exch pop}
         ]
      >> setcolorrendering
      [/CIEBasedA << /WhitePoint [1 1 1] /MatrixA [1 1 1] >>] setcolorspace
      .5 setcolor 0 0 1 1 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )

    guard case .fillRectangles(_, let state) = try #require(result.output.pages.first?.effects.first)
    else {
      Issue.record("Expected a color-rendered fill")
      return
    }
    let rgb = state.paint.rgbComponents
    #expect(abs(rgb.red - 0.25) < 1e-12)
    #expect(abs(rgb.green - 0.25) < 1e-12)
    #expect(abs(rgb.blue - 0.25) < 1e-12)
  }

  @Test func generalizedImagesRetainSourceSamplesAndEvaluatedAlternatives() async throws {
    let result = try await Interpreter.render(
      content: """
      [/Separation /Spot /DeviceRGB {dup 1 exch sub 0}] setcolorspace
      << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
         /ImageMatrix [1 0 0 1 0 0] /Decode [0 1] /DataSource <40>
      >> image showpage
      """,
      to: RecordingGraphicsTarget()
    )

    guard case .image(let image, _) = try #require(result.output.pages.first?.effects.first)
    else {
      Issue.record("Expected a generalized sampled image")
      return
    }
    #expect(image.descriptor.sourceColorSpace == .separation(name: "Spot", alternative: .deviceRGB))
    #expect(image.sourceComponents == [Float(64.0 / 255.0)])
    #expect(image.components.count == 3)
    #expect(abs(image.components[0] - Float(64.0 / 255.0)) < 0.000_001)
    #expect(abs(image.components[1] - Float(191.0 / 255.0)) < 0.000_001)
    #expect(image.components[2] == 0)
  }

  @Test func malformedColorOperandsUseTheLanguageErrorLifecycle() async throws {
    let values = try await Interpreter.results(
      content: """
      {[/CIEBasedA << /WhitePoint [0 1 1] >>] setcolorspace} stopped
      $error /errorname get $error /command get /setcolorspace load eq
      """
    )
    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: NameValue.self).value == "rangecheck")
    #expect(try values[2].value(as: BooleanValue.self).value)
  }
}
