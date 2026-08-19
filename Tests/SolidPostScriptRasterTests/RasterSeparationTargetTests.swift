import Testing

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
}
