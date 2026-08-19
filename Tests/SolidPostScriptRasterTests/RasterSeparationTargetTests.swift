import Testing

import SolidColor
@testable import SolidPostScript
@testable import SolidPostScriptRaster

@Suite
struct RasterSeparationTargetTests {
  @Test func targetPreservesTypedPageOutputAndCompositePreview() async throws {
    let result = try await Interpreter.render(
      content: "0 setgray 0 0 2 2 rectfill showpage",
      to: RasterSeparationTarget(
        deviceDescriptor: GraphicsDeviceDescriptor(
          mediaBounds: GraphicsRect(x: 0, y: 0, width: 2, height: 2),
          imageableBounds: GraphicsRect(x: 0, y: 0, width: 2, height: 2),
          horizontalResolution: 72,
          verticalResolution: 72,
          defaultMatrix: .identity
        )
      )
    )

    let page = try #require(result.output.first)
    #expect(page.compositePreview.width == 2)
    #expect(page.compositePreview.height == 2)
    #expect(page.device.descriptor.colorants.processModel == .deviceCMYK)
    #expect(page.plates.map(\.colorant) == ["Cyan", "Magenta", "Yellow", "Black"])
  }

  @Test func pageDeviceSelectsProcessAndNamedColorantsInExactOrder() async throws {
    let target = RasterSeparationTarget()
    let session = try target.pageDeviceProvider.makeSession(for: target.deviceDescriptor)
    #expect(target.deviceDescriptor.colorants.processModel == .deviceCMYK)
    #expect(session.initialConfiguration.colorants.processModel == .deviceCMYK)
    #expect(session.capabilities.colorants.supportsSeparationOutput)
    let result = try await Interpreter.render(
      content: """
        << /ProcessColorModel /DeviceCMYK
           /Separations true
           /SeparationColorNames [(Varnish) /Spot /Varnish]
           /SeparationOrder [/Black /Varnish /Black /Spot]
        >> setpagedevice
        currentpagedevice
      """,
      to: target
    )
    let dictionary = try #require(try await result.context.results().first)
      .value(as: DictionaryValue.self)
    let names = try dictionary.objectValue(forKey: "SeparationColorNames", as: ArrayValue.self)
    let order = try dictionary.objectValue(forKey: "SeparationOrder", as: ArrayValue.self)

    #expect(try dictionary.objectValue(forKey: "ProcessColorModel", as: NameValue.self).value == "DeviceCMYK")
    #expect(try dictionary.objectValue(forKey: "Separations", as: BooleanValue.self).value)
    #expect(try names.object(at: 0).value(as: NameValue.self).value == "Varnish")
    #expect(try names.object(at: 1).value(as: NameValue.self).value == "Spot")
    #expect(try order.objects(in: order.range, for: .read).map { try $0.value(as: NameValue.self).value }
      == ["Black", "Varnish", "Black", "Spot"])
  }

  @Test func compositeImageTargetRejectsSeparationOutputThroughPolicy() async throws {
    let result = try await Interpreter.render(
      content: """
        { << /Policies << /Separations 0 >> /Separations true >> setpagedevice } stopped
        $error /errorname get
      """,
      to: RasterImageTarget()
    )
    let values = try await result.context.results()

    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: NameValue.self).value == "configurationerror")
  }

  @Test func availableNamedColorantsBypassTheirAlternativeTransforms() async throws {
    let result = try await Interpreter.render(
      content: """
        << /SeparationColorNames [/Varnish /Spot] >> setpagedevice
        [/Separation /Varnish /DeviceCMYK { 1 0 div }] setcolorspace
        .25 setcolor currentcolor
        [/DeviceN [/Varnish /Spot] /DeviceCMYK { 1 0 div }] setcolorspace
        .5 .75 setcolor currentcolor
      """,
      to: RasterSeparationTarget()
    )
    let values = try await result.context.results()

    #expect(try values[2].value(as: RealValue.self).value == 0.25)
    #expect(try values[1].value(as: RealValue.self).value == 0.5)
    #expect(try values[0].value(as: RealValue.self).value == 0.75)
  }

  @Test func unavailableNamedColorantsUseTheCompleteAlternativeTransform() async throws {
    let result = try await Interpreter.render(
      content: """
        { [/Separation /Unavailable /DeviceCMYK { 1 0 div }] setcolorspace } stopped
        $error /errorname get
      """,
      to: RasterSeparationTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: NameValue.self).value == "undefinedresult")
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func processPaintsApplyKnockoutAndOverprintPerPlate() async throws {
    let result = try await Interpreter.render(
      content: """
        0 1 0 0 setcmykcolor 0 0 4 2 rectfill
        false setoverprint 1 0 0 0 setcmykcolor 0 0 2 2 rectfill
        true setoverprint 0 0 1 0 setcmykcolor 2 0 2 2 rectfill
        showpage
      """,
      to: smallTarget(width: 4, height: 2)
    )
    let page = try #require(result.output.first)
    let plates = Dictionary(uniqueKeysWithValues: page.plates.map { ($0.colorant, $0.tint) })

    #expect(plates["Cyan"]?.data[0] == 255)
    #expect(plates["Magenta"]?.data[0] == 0)
    #expect(plates["Yellow"]?.data[0] == 0)
    #expect(plates["Magenta"]?.data[3] == 255)
    #expect(plates["Yellow"]?.data[3] == 255)
    #expect(plates["Black"]?.data.allSatisfy { $0 == 0 } == true)
  }

  @Test func diagnosticPreviewUsesTheSelectedProcessModel() async throws {
    let result = try await Interpreter.render(
      content: """
        << /ProcessColorModel /DeviceRGB
           /SeparationOrder [/Red /Green /Blue]
        >> setpagedevice
        1 0 0 setrgbcolor 0 0 1 1 rectfill showpage
      """,
      to: smallTarget(width: 1, height: 1)
    )
    let preview = try #require(result.output.first?.compositePreview)

    #expect(Array(preview.data.prefix(4)) == [255, 0, 0, 255])
  }

  @Test func deviceNProcessConversionRequiresAndUsesTheConfiguredLookup() async throws {
    let defaultTarget = smallTarget(width: 1, height: 1)
    let defaultSession = try defaultTarget.pageDeviceProvider.makeSession(for: defaultTarget.deviceDescriptor)
    #expect(!defaultSession.capabilities.colorants.supportedProcessModels.contains(.deviceN))
    #expect(throws: SolidPostScript.Error.configurationError) {
      _ = try RasterSeparationTarget(
        deviceDescriptor: defaultTarget.deviceDescriptor,
        colorantConfiguration: GraphicsColorantConfiguration(
          processModel: .deviceN,
          additionalColorants: [GraphicsColorant(name: "Orange", isProcessColorant: true)]
        )
      ).makeRenderer()
    }

    let lookup = try ColorLookupTable(
      dimensions: [2, 2, 2],
      outputComponentCount: 2,
      values: Array(repeating: [0.25, 0.75], count: 8).flatMap { $0 }
    )
    let bounds = GraphicsRect(x: 0, y: 0, width: 1, height: 1)
    let configuration = GraphicsColorantConfiguration(
      processModel: .deviceN,
      producesSeparations: true,
      additionalColorants: [
        GraphicsColorant(name: "Orange", isProcessColorant: true),
        GraphicsColorant(name: "Green", isProcessColorant: true),
      ],
      separationOrder: ["Orange", "Green"],
      maximumSeparations: 2,
      supportsOverprint: true,
      rgbToDeviceN: lookup
    )
    let target = RasterSeparationTarget(
      deviceDescriptor: GraphicsDeviceDescriptor(
        mediaBounds: bounds,
        imageableBounds: bounds,
        horizontalResolution: 72,
        verticalResolution: 72,
        defaultMatrix: .identity
      ),
      colorantConfiguration: configuration
    )
    let session = try target.pageDeviceProvider.makeSession(for: target.deviceDescriptor)
    let result = try await Interpreter.render(
      content: "1 0 0 setrgbcolor 0 0 1 1 rectfill showpage",
      to: target
    )
    let page = try #require(result.output.first)

    #expect(session.capabilities.colorants.supportedProcessModels.contains(.deviceN))
    #expect(page.plates[0].tint.data[0] == 64)
    #expect(page.plates[1].tint.data[0] == 191)
  }

  @Test func compositeModeAndCopiesTransmitOnlySharedDiagnosticOutput() async throws {
    let result = try await Interpreter.render(
      content: """
        << /Separations false /NumCopies 2 >> setpagedevice
        0 setgray 0 0 1 1 rectfill showpage
      """,
      to: smallTarget(width: 1, height: 1)
    )

    #expect(result.output.count == 2)
    #expect(result.output.allSatisfy { $0.plates.isEmpty })
    #expect(result.output[0].compositePreview == result.output[1].compositePreview)
  }

  @Test func namedInkPreviewUsesTheProviderColorWithoutEvaluatingItsAlternative() async throws {
    let bounds = GraphicsRect(x: 0, y: 0, width: 1, height: 1)
    let target = RasterSeparationTarget(
      deviceDescriptor: GraphicsDeviceDescriptor(
        mediaBounds: bounds,
        imageableBounds: bounds,
        horizontalResolution: 72,
        verticalResolution: 72,
        defaultMatrix: .identity
      ),
      colorantConfiguration: GraphicsColorantConfiguration(
        processModel: .deviceCMYK,
        producesSeparations: true,
        additionalColorants: [GraphicsColorant(
          name: "Varnish",
          isProcessColorant: false,
          previewColor: ColorRGB(red: 0, green: 1, blue: 0)
        )],
        separationOrder: ["Varnish"],
        maximumSeparations: 5,
        supportsOverprint: true
      )
    )
    let result = try await Interpreter.render(
      content: """
        [/Separation /Varnish /DeviceCMYK { 1 0 div }] setcolorspace
        1 setcolor 0 0 1 1 rectfill showpage
      """,
      to: target
    )
    let page = try #require(result.output.first)

    #expect(page.plates.map(\.colorant) == ["Varnish"])
    #expect(Array(page.compositePreview.data.prefix(4)) == [0, 255, 0, 255])
  }

  @Test func noneIsANoOpAndDirectSpotNeverRunsItsAlternative() async throws {
    let result = try await Interpreter.render(
      content: """
        << /SeparationColorNames [/Varnish]
           /SeparationOrder [/Magenta /Varnish /Magenta]
        >> setpagedevice
        0 1 0 0 setcmykcolor 0 0 2 2 rectfill
        [/Separation /None /DeviceCMYK { 1 0 div }] setcolorspace
        1 setcolor 0 0 1 2 rectfill
        1 1 true [1 0 0 1 0 0] <80> imagemask
        [/Separation /Varnish /DeviceCMYK { 1 0 div }] setcolorspace
        .5 setcolor 1 0 1 2 rectfill
        showpage
      """,
      to: smallTarget(width: 2, height: 2)
    )
    let page = try #require(result.output.first)

    #expect(page.plates.map(\.colorant) == ["Magenta", "Varnish", "Magenta"])
    #expect(page.plates[0].tint.data[0] == 255)
    #expect(page.plates[0].tint.data[1] == 0)
    #expect(page.plates[1].tint.data[0] == 0)
    #expect(page.plates[1].tint.data[1] == 128)
    #expect(page.plates[0].tint == page.plates[2].tint)
  }

  @Test func stencilImagesApplyPaintTintAndMaskCoverage() async throws {
    let result = try await Interpreter.render(
      content: """
        0 0 0 1 setcmykcolor
        2 1 true [1 0 0 1 0 0] { <80> } imagemask
        showpage
      """,
      to: smallTarget(width: 2, height: 1)
    )
    let black = try #require(result.output.first?.plates.last?.tint)

    #expect(black.data[0] == 255)
    #expect(black.data[1] == 0)
  }

  @Test func formsPatternsAndShadingsReplayIntoAuthoritativePlates() async throws {
    let result = try await Interpreter.render(
      content: """
        /f << /FormType 1 /BBox [0 0 2 2] /Matrix [1 0 0 1 0 0]
              /PaintProc { pop 1 0 0 0 setcmykcolor 0 0 2 2 rectfill } >> def
        f execform
        /p << /PatternType 1 /PaintType 1 /TilingType 1
              /BBox [0 0 2 2] /XStep 2 /YStep 2
              /PaintProc { pop 0 1 0 0 setcmykcolor 0 0 2 2 rectfill }
            >> matrix makepattern def
        /Pattern setcolorspace p setcolor 2 0 2 2 rectfill
        gsave 4 0 2 4 rectclip
          << /ShadingType 2 /ColorSpace /DeviceCMYK /Coords [4 0 6 0]
             /Function << /FunctionType 2 /Domain [0 1]
                          /C0 [0 0 1 0] /C1 [0 0 1 0] /N 1 >>
             /Extend [true true] >> shfill
        grestore showpage
      """,
      to: smallTarget(width: 6, height: 4)
    )
    let plates = Dictionary(uniqueKeysWithValues: try #require(result.output.first).plates.map {
      ($0.colorant, $0.tint)
    })

    #expect(plates["Cyan"]?.data[19] == 255)
    #expect(plates["Magenta"]?.data[21] == 255)
    #expect((plates["Yellow"]?.data[17] ?? 0) > 128)
  }

  @Test func concurrentSeparationRendersSharingAnEnvironmentRemainIndependent() async throws {
    let environment = InterpreterEnvironment()
    async let cyan = Interpreter.render(
      content: "1 0 0 0 setcmykcolor 0 0 2 2 rectfill showpage",
      to: smallTarget(width: 2, height: 2),
      environment: environment
    )
    async let magenta = Interpreter.render(
      content: "0 1 0 0 setcmykcolor 0 0 2 2 rectfill showpage",
      to: smallTarget(width: 2, height: 2),
      environment: environment
    )
    let (cyanResult, magentaResult) = try await (cyan, magenta)
    let cyanPlates = try #require(cyanResult.output.first?.plates)
    let magentaPlates = try #require(magentaResult.output.first?.plates)

    #expect(cyanPlates[0].tint.data.allSatisfy { $0 == 255 })
    #expect(cyanPlates[1].tint.data.allSatisfy { $0 == 0 })
    #expect(magentaPlates[0].tint.data.allSatisfy { $0 == 0 })
    #expect(magentaPlates[1].tint.data.allSatisfy { $0 == 255 })
  }

  private func smallTarget(width: Int, height: Int) -> RasterSeparationTarget {
    let bounds = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    return RasterSeparationTarget(deviceDescriptor: GraphicsDeviceDescriptor(
      mediaBounds: bounds,
      imageableBounds: bounds,
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    ))
  }
}
