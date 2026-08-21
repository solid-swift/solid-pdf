import Testing

@testable import SolidPostScript

@Suite
struct GraphicsSemanticsTests {

  @Test func smoothnessClampsToDeviceAndSurvivesGraphicsState() async throws {
    let device = GraphicsDeviceDescriptor(
      mediaBounds: .init(x: 0, y: 0, width: 10, height: 10),
      imageableBounds: .init(x: 0, y: 0, width: 10, height: 10),
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity,
      minimumSmoothness: 0.1,
      maximumSmoothness: 0.8,
      defaultSmoothness: 0.2
    )
    let result = try await Interpreter.render(
      content: "0 setsmoothness gsave 1 setsmoothness grestore currentsmoothness gstate 1 setsmoothness setgstate currentsmoothness",
      to: RecordingGraphicsTarget(deviceDescriptor: device)
    )
    let values = try await result.context.results().map { try $0.value(as: RealValue.self).value }
    #expect(values == [0.1, 0.1])
  }

  @Test func graphicsStateOperatorsRestoreAndCopyState() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      2 setlinewidth
      gsave 5 setlinewidth grestore currentlinewidth
      save 7 setlinewidth restore currentlinewidth
      gstate 9 setlinewidth currentgstate 4 setlinewidth setgstate currentlinewidth
      gstate 11 setlinewidth currentgstate gstate copy setgstate currentlinewidth
      """,
      count: 4
    )

    #expect(values.map(\.value) == [11, 9, 2, 2])
  }

  @Test func lineAndGrayStateValidation() async throws {
    let result = try await Interpreter.render(
      content: """
      4 setlinewidth 1 setlinecap 2 setlinejoin 12 setmiterlimit
      [3 2] 1 setdash .25 setgray
      currentgray currentdash currentmiterlimit currentlinejoin currentlinecap currentlinewidth
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: RealValue.self).value == 4)
    #expect(try values[1].value(as: IntegerValue.self).value == 1)
    #expect(try values[2].value(as: IntegerValue.self).value == 2)
    #expect(try values[3].value(as: RealValue.self).value == 12)
    #expect(try values[4].value(as: RealValue.self).value == 1)
    #expect(try values[6].value(as: RealValue.self).value == 0.25)
  }

  @Test func matricesTransformPointsAndDistances() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: """
      10 20 translate 2 3 scale
      1 2 transform
      1 2 dtransform
      12 26 itransform
      2 6 idtransform
      """,
      count: 8
    )

    let expected: [Double] = [2, 1, 2, 1, 6, 2, 26, 12]
    for (actual, expected) in zip(values.map(\.value), expected) {
      #expect(abs(actual - expected) < 1e-12)
    }
  }

  @Test func pathsAreConstructedInDeviceSpaceAndClearedByPaint() async throws {
    let result = try await Interpreter.render(
      content: "2 3 scale 10 20 moveto 5 7 rlineto stroke showpage",
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .stroke(let path, let state) = try #require(page.effects.first) else {
      Issue.record("Expected a stroke effect")
      return
    }

    #expect(path.elements == [
      .move(to: GraphicsPoint(x: 20, y: 60)),
      .line(to: GraphicsPoint(x: 30, y: 81)),
    ])
    #expect(state.matrix == GraphicsMatrix(a: 2, b: 0, c: 0, d: 3, tx: 0, ty: 0))
  }

  @Test func closepathIsIdempotentAndPostCloseSegmentsBeginANewSubpath() async throws {
    let result = try await Interpreter.render(
      content: "0 0 moveto 10 0 lineto closepath closepath 20 0 lineto stroke showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .stroke(let path, _) = try #require(result.output.pages.first?.effects.first) else {
      Issue.record("Expected a stroke effect")
      return
    }
    #expect(path.elements == [
      .move(to: GraphicsPoint(x: 0, y: 0)),
      .line(to: GraphicsPoint(x: 10, y: 0)),
      .close,
      .move(to: GraphicsPoint(x: 0, y: 0)),
      .line(to: GraphicsPoint(x: 20, y: 0)),
    ])
  }

  @Test func clippingPreservesThePathAndClipRestoreUsesSavedGraphicsState() async throws {
    let values = try await Interpreter.results(content: """
      gsave 0 0 moveto 10 0 lineto 10 20 lineto closepath clip pathbbox
      newpath cliprestore clippath pathbbox grestore
      """)
    let numbers = values.compactMap { try? Operators.numeric($0) }
    #expect(numbers.prefix(4).elementsEqual([792, 612, 0, 0]))
    #expect(numbers.suffix(4).elementsEqual([20, 10, 0, 0]))
  }

  @Test func emptyGRestoreAllIsANoOp() async throws {
    let value: RealValue = try await Interpreter.result(content: "5 setlinewidth grestoreall currentlinewidth")
    #expect(value.value == 5)
  }

  @Test func clippingAndPageTransmissionAreRecorded() async throws {
    let result = try await Interpreter.render(
      content: """
      newpath 0 0 moveto 100 0 lineto 100 100 lineto closepath clip
      .5 setgray newpath 10 10 moveto 20 10 lineto 20 20 lineto closepath fill
      showpage showpage
      newpath 0 0 moveto 1 1 lineto stroke
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.count == 2)
    #expect(result.output.pages[0].effects.count == 1)
    #expect(result.output.pages[1].effects.isEmpty)
    guard case .fill(_, .winding, let state) = try #require(result.output.pages[0].effects.first) else {
      Issue.record("Expected a fill effect")
      return
    }
    #expect(state.clip.constraints.count == 1)
  }

  @Test func errorsUseLanguageErrorLifecycle() async throws {
    let error: NameValue = try await Interpreter.result(
      content: "{0 0 lineto} stopped $error /errorname get"
    )
    #expect(error.value == "nocurrentpoint")
  }

  @Test func globalGraphicsStateRejectsLocalDashStorage() async {
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "false setglobal [1] 0 setdash true setglobal gstate")
    }
  }

  @Test func rendererFailureBecomesIOError() async {
    await #expect(throws: Error.ioError) {
      try await Interpreter.render(
        content: "newpath 0 0 moveto 10 0 lineto stroke",
        to: FailingGraphicsTarget()
      )
    }
  }

  @Test func eventsPreserveOperationIntentAndStateTransition() async throws {
    let result = try await Interpreter.render(
      content: "2 setlinewidth 1 1 moveto 3 4 rlineto stroke showpage",
      to: EventGraphicsTarget()
    )

    #expect(result.output.map(\.operation) == [
      .state(.setLineWidth(2)),
      .path(.move(to: GraphicsPoint(x: 1, y: 1))),
      .path(.relativeLine(dx: 3, dy: 4)),
      .paint(.stroke),
      .page(.show),
    ])
    let stroke = result.output[3]
    #expect(stroke.before.path.currentPoint == GraphicsPoint(x: 4, y: 5))
    #expect(stroke.after.path.isEmpty)
  }

  @Test func deviceColorsClampAndConvertAccordingToPLRM() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: "1.5 -.5 .25 setrgbcolor currentrgbcolor currentgray currentcmykcolor",
      count: 8
    )
    let actual = values.map(\.value).reversed()
    let expected = [1.0, 0.0, 0.25, 0.3275, 0.0, 1.0, 0.75, 0.0]
    for (actual, expected) in zip(actual, expected) {
      #expect(abs(actual - expected) < 1e-12)
    }
  }

  @Test func arcsAndTangentArcsAppendDeviceSpaceCurves() async throws {
    let result = try await Interpreter.render(
      content: "0 0 moveto 10 10 5 0 180 arc 20 10 20 20 2 arcto currentpoint",
      to: EventGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(values.count == 6)
    #expect(result.output.contains { event in
      if case .path(.arc(center: GraphicsPoint(x: 10, y: 10), radius: 5, startDegrees: 0, endDegrees: 180)) =
        event.operation
      {
        return true
      }
      return false
    })
    #expect(result.output.contains { event in
      if case .path(.arcTo) = event.operation { return true }
      return false
    })
  }

  @Test func rectangleOperatorsBatchAndPreserveOrClearTheCurrentPath() async throws {
    let result = try await Interpreter.render(
      content: "1 1 moveto [0 0 10 10 12 0 -2 5] rectfill currentpoint 0 0 20 20 rectclip",
      to: EventGraphicsTarget()
    )
    let values = try await result.context.results()
    let numbers = try values.map { try $0.value(as: RealValue.self).value }
    #expect(numbers.reversed() == [1, 1])
    #expect(result.output.contains { event in
      if case .paint(.fillRectangles(let paths)) = event.operation { return paths.count == 2 }
      return false
    })
    #expect(result.output.last?.after.path.isEmpty == true)
  }

  @Test func copyPageErasesAtLanguageLevelThreeWithoutResettingGraphicsState() async throws {
    let result = try await Interpreter.render(
      content: "4 setlinewidth 0 0 10 10 rectfill copypage currentlinewidth showpage",
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(try values.first?.value(as: RealValue.self).value == 4)
    #expect(result.output.pages.count == 2)
    #expect(result.output.pages[0].effects.count == 1)
    #expect(result.output.pages[1].effects.count == 1)
    guard case .erase = result.output.pages[1].effects[0] else {
      Issue.record("Expected copypage to erase the retained page")
      return
    }
  }

  @Test func sampledImagesUseBoundedNormalizedTransfers() async throws {
    let result = try await Interpreter.render(
      content: "2 2 8 [2 0 0 2 0 0] <00ff> image showpage",
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .image(let image, _) = try #require(page.effects.first) else {
      Issue.record("Expected an image effect")
      return
    }
    #expect(image.descriptor.width == 2)
    #expect(image.descriptor.height == 2)
    #expect(image.components == [0, 1, 0, 1])
  }

  @Test func imageDictionaryAndColorImagePreserveComponentModels() async throws {
    let dictionaryResult = try await Interpreter.render(
      content: "0 0 1 setrgbcolor << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8 "
        + "/ImageMatrix [1 0 0 1 0 0] /Decode [0 1 0 1 0 1] /DataSource <ff8000> >> image showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let dictionaryImage, _) = try #require(dictionaryResult.output.pages.first?.effects.first) else {
      Issue.record("Expected a dictionary image effect")
      return
    }
    #expect(dictionaryImage.descriptor.kind == .color(.deviceRGB))
    #expect(dictionaryImage.components == [1, Float(128.0 / 255.0), 0])

    let colorResult = try await Interpreter.render(
      content: "1 1 8 [1 0 0 1 0 0] <00ff00> false 3 colorimage showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let colorImage, _) = try #require(colorResult.output.pages.first?.effects.first) else {
      Issue.record("Expected a colorimage effect")
      return
    }
    #expect(colorImage.descriptor.kind == .color(.deviceRGB))
    #expect(colorImage.components == [0, 1, 0])
  }

  @Test func imageSamplesSupportTwelveBitsMasksPlanarSourcesAndPrematureEnd() async throws {
    let twelveBit = try await Interpreter.render(
      content: "2 1 12 [2 0 0 1 0 0] <000fff> image showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let twelveBitImage, _) = try #require(twelveBit.output.pages.first?.effects.first) else {
      Issue.record("Expected a 12-bit image effect")
      return
    }
    #expect(twelveBitImage.components == [0, 1])

    let mask = try await Interpreter.render(
      content: "1 0 0 setrgbcolor 2 1 true [2 0 0 1 0 0] <80> imagemask showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let maskImage, _) = try #require(mask.output.pages.first?.effects.first) else {
      Issue.record("Expected an imagemask effect")
      return
    }
    #expect(maskImage.descriptor.kind == .mask(.deviceRGB(red: 1, green: 0, blue: 0)))
    #expect(maskImage.components == [1, 0])

    let planar = try await Interpreter.render(
      content: "1 1 8 [1 0 0 1 0 0] <ff> <00> <80> true 3 colorimage showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let planarImage, _) = try #require(planar.output.pages.first?.effects.first) else {
      Issue.record("Expected a planar colorimage effect")
      return
    }
    #expect(planarImage.components == [1, 0, Float(128.0 / 255.0)])

    let partial = try await Interpreter.render(
      content: "/n 0 def 2 2 8 [2 0 0 2 0 0] {n 0 eq {/n 1 def <00ff>} {<>} ifelse} image showpage",
      to: RecordingGraphicsTarget()
    )
    guard case .image(let partialImage, _) = try #require(partial.output.pages.first?.effects.first) else {
      Issue.record("Expected a partial image effect")
      return
    }
    #expect(partialImage.components == [0, 1])
  }

  @Test func fileImageSourcesConsumeOnlyRequiredBytes() async throws {
    let values = try await Interpreter.results(
      content: "/f (ABC) /ReusableStreamDecode filter def "
        + "2 1 8 [2 0 0 1 0 0] f image f read"
    )
    #expect(try values[0].value(as: IntegerValue.self).value == 67)
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func imageSourcesShareTheLogicalCursorAndFailedTransfersCanRecover() async throws {
    let inline = try await Interpreter.render(
      content: "1 1 8 [1 0 0 1 0 0] currentfile image A 42 showpage",
      to: RecordingGraphicsTarget()
    )
    let inlineValues = try await inline.context.results()
    #expect(try inlineValues.first?.value(as: IntegerValue.self).value == 42)
    guard case .image(let inlineImage, _) = try #require(inline.output.pages.first?.effects.first) else {
      Issue.record("Expected an inline image effect")
      return
    }
    #expect(inlineImage.components == [Float(65.0 / 255.0)])

    let recovered = try await Interpreter.render(
      content: "{1 1 8 [1 0 0 1 0 0] {doesnotexist} image} stopped pop "
        + "1 1 8 [1 0 0 1 0 0] <ff> image showpage",
      to: RecordingGraphicsTarget()
    )
    let page = try #require(recovered.output.pages.first)
    #expect(page.effects.count == 1)
    guard case .image(let recoveredImage, _) = try #require(page.effects.first) else {
      Issue.record("Expected the recovered image effect")
      return
    }
    #expect(recoveredImage.components == [1])
  }

  @Test func imageProceduresMustRemainSynchronizedAndCannotPerformGraphics() async throws {
    let synchronized = try await Interpreter.results(
      content: """
      /DeviceRGB setcolorspace
      { << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
           /ImageMatrix [1 0 0 1 0 0] /Decode [0 1 0 1 0 1]
           /MultipleDataSources true
           /DataSource [{<00>} {<0000>} {<00>}]
        >> image } stopped
      $error /errorname get
      """
    )
    #expect(try synchronized[0].value(as: NameValue.self).value == "rangecheck")
    #expect(try synchronized[1].value(as: BooleanValue.self).value)

    let graphics = try await Interpreter.results(
      content: "{ 1 1 8 [1 0 0 1 0 0] {0 setgray <ff>} image } stopped $error /errorname get"
    )
    #expect(try graphics[0].value(as: NameValue.self).value == "undefined")
    #expect(try graphics[1].value(as: BooleanValue.self).value)
  }

  @Test func imageProceduresCannotMutateTheActiveImageDictionary() async throws {
    let values = try await Interpreter.results(
      content: """
      /d << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
            /ImageMatrix [1 0 0 1 0 0] /Decode [0 1] >> def
      d /DataSource {d /Width 2 put <ff>} put
      {d image} stopped $error /errorname get
      """
    )
    #expect(try values[0].value(as: NameValue.self).value == "undefined")
    #expect(try values[1].value(as: BooleanValue.self).value)
  }

  @Test func planarFileSourcesMustHaveDistinctUltimateSources() async throws {
    let values = try await Interpreter.results(
      content: """
      /source (000000>) /ReusableStreamDecode filter def
      /red source /ASCIIHexDecode filter def
      /green source /ASCIIHexDecode filter def
      /blue (<00>) /ASCIIHexDecode filter def
      /DeviceRGB setcolorspace
      { << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 8
           /ImageMatrix [1 0 0 1 0 0] /Decode [0 1 0 1 0 1]
           /MultipleDataSources true /DataSource [red green blue]
        >> image } stopped
      $error /errorname get
      """
    )
    #expect(try values[0].value(as: NameValue.self).value == "rangecheck")
    #expect(try values[1].value(as: BooleanValue.self).value)
  }
}

private struct EventGraphicsTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = [GraphicsEvent]

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = [GraphicsEvent]

    var pages: [Void] = []
    private var events: [GraphicsEvent] = []

    func process(_ event: GraphicsEvent) {
      events.append(event)
      if case .page(.show) = event.operation { pages.append(()) }
    }

    func finish() -> sending [GraphicsEvent] { events }
    func abort() { events.removeAll() }
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}

private struct FailingGraphicsTarget: GraphicsTarget {
  typealias PageOutput = Void
  typealias Output = Void

  final class Renderer: GraphicsRenderer {
    typealias PageOutput = Void
    typealias Output = Void

    var pages: [Void] { [] }

    func process(_ event: GraphicsEvent) throws {
      if case .paint = event.operation { throw Failure() }
    }

    func finish() -> sending Void {}
    func abort() {}
  }

  let deviceDescriptor = GraphicsDeviceDescriptor.letter

  func makeRenderer() -> sending Renderer { Renderer() }
}

private struct Failure: Swift.Error {}
