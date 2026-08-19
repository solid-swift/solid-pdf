import Testing

@testable import SolidPostScript

@Suite
struct PageDeviceTests {
  @Test func operatorsAreRegistered() async throws {
    let values = try await Interpreter.results(
      content: "/setpagedevice where /currentpagedevice where /nulldevice where"
    )

    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[2].value(as: BooleanValue.self).value)
    #expect(try values[4].value(as: BooleanValue.self).value)
  }

  @Test func currentPageDeviceReportsVirtualDefaults() async throws {
    let values = try await Interpreter.results(content: """
      currentpagedevice
      dup /PageSize get aload pop
      3 -1 roll /HWResolution get aload pop
      """)

    #expect(try values[0].value(as: RealValue.self).value == 72)
    #expect(try values[1].value(as: RealValue.self).value == 72)
    #expect(try values[2].value(as: RealValue.self).value == 792)
    #expect(try values[3].value(as: RealValue.self).value == 612)
  }

  @Test func trappingCapabilitiesNegotiateThroughPageDevice() throws {
    let provider = StandardGraphicsPageDeviceProvider(
      trappingCapabilities: .semanticType1001
    )
    let session = try provider.makeSession(for: .letter)
    let result = try session.negotiate(GraphicsPageDeviceRequest(
      pageSize: session.initialConfiguration.pageSize,
      resolution: GraphicsSize(width: 72, height: 72),
      imagingBoundingBox: nil,
      numberOfCopies: 1,
      trappingEnabled: true,
      trappingDetails: GraphicsTrappingDetails(type: 1001)
    ))

    #expect(result.unsatisfiedParameters.isEmpty)
    #expect(result.configuration.trappingEnabled)
    #expect(result.configuration.trappingDetails.type == 1001)
  }

  @Test func outputDeviceResourceIsAutomaticAndContextLocal() async throws {
    let values = try await Interpreter.results(content: """
      /SolidVirtualPageDevice /OutputDevice resourcestatus { pop 1 eq } { false } ifelse
      """)

    #expect(try values[0].value(as: BooleanValue.self).value)
  }

  @Test func adaptiveSetPageDeviceChangesGeometry() async throws {
    let result = try await Interpreter.render(
      content: """
        << /PageSize [300 400] /HWResolution [144 144] /NumCopies 2 >> setpagedevice
        currentpagedevice /PageSize get aload pop
        currentpagedevice /HWResolution get aload pop
        currentpagedevice /NumCopies get
        """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: IntegerValue.self).value == 2)
    #expect(try values[1].value(as: RealValue.self).value == 144)
    #expect(try values[2].value(as: RealValue.self).value == 144)
    #expect(try values[3].value(as: RealValue.self).value == 400)
    #expect(try values[4].value(as: RealValue.self).value == 300)
  }

  @Test func providerComputesAStorageBoundedSeparationMaximum() throws {
    let descriptor = GraphicsDeviceDescriptor(
      mediaBounds: GraphicsRect(x: 0, y: 0, width: 10, height: 10),
      imageableBounds: GraphicsRect(x: 0, y: 0, width: 10, height: 10),
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    )
    let session = try StandardGraphicsPageDeviceProvider(
      maximumSurfaceBytes: 400,
      colorantCapabilities: GraphicsColorantCapabilities(
        supportedProcessModels: [.deviceRGB, .deviceCMYK],
        supportsSeparationOutput: true,
        supportsOverprint: true,
        acceptsDynamicColorants: true,
        maximumSeparations: 250
      )
    ).makeSession(for: descriptor)
    let negotiation = try session.negotiate(GraphicsPageDeviceRequest(
      pageSize: GraphicsSize(width: 10, height: 10),
      resolution: GraphicsSize(width: 72, height: 72),
      imagingBoundingBox: nil,
      numberOfCopies: 1,
      colorants: GraphicsColorantConfiguration(
        processModel: .deviceCMYK,
        producesSeparations: true,
        additionalColorants: [GraphicsColorant(name: "Spot", isProcessColorant: false)],
        separationOrder: ["Cyan", "Magenta", "Yellow", "Black", "Spot"],
        maximumSeparations: 250,
        supportsOverprint: true
      )
    ))

    #expect(negotiation.configuration.colorants.maximumSeparations == 4)
    #expect(negotiation.unsatisfiedParameters == ["SeparationOrder"])
  }

  @Test func ignoredUnknownParameterInvokesPolicyReport() async throws {
    let values = try await Interpreter.results(content: """
      /reported false def
      << /Policies << /Mystery 1 /PolicyReport { pop /reported true def } >>
         /Mystery 99
      >> setpagedevice
      reported
      """)

    #expect(try values[0].value(as: BooleanValue.self).value)
  }

  @Test func policyZeroProducesConfigurationErrorInfo() async throws {
    let values = try await Interpreter.results(content: """
      { << /Policies << /Mystery 0 >> /Mystery 99 >> setpagedevice } stopped
      $error /errorname get
      $error /errorinfo get 0 get
      """)

    #expect(try values[2].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: NameValue.self).value == "configurationerror")
    #expect(try values[0].value(as: NameValue.self).value == "Mystery")
  }

  @Test func nullDeviceHasIdentityMatrixAndEmptyPageDictionary() async throws {
    let values = try await Interpreter.results(content: """
      nulldevice
      currentpagedevice length
      matrix currentmatrix aload pop
      """)

    #expect(try values[6].value(as: IntegerValue.self).value == 0)
    #expect(try values[5].value(as: RealValue.self).value == 1)
    #expect(try values[4].value(as: RealValue.self).value == 0)
    #expect(try values[3].value(as: RealValue.self).value == 0)
    #expect(try values[2].value(as: RealValue.self).value == 1)
  }

  @Test func pageLifecycleUsesCountsReasonsAndConfiguredCopies() async throws {
    let result = try await Interpreter.render(
      content: """
        /begins 0 def /lastBegin -1 def /lastReason -1 def
        << /NumCopies 2
           /BeginPage { /lastBegin exch def /begins begins 1 add def }
           /EndPage { /lastReason exch def pop lastReason 2 ne }
        >> setpagedevice
        showpage
        begins lastBegin
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(result.output.pages.count == 2)
    #expect(try values[0].value(as: IntegerValue.self).value == 1)
    #expect(try values[1].value(as: IntegerValue.self).value == 2)
    let lastReason: IntegerValue = try await result.context.currentDictionary()
      .objectValue(forKey: "lastReason")
    #expect(lastReason.value == 2)
  }

  @Test func customEndPageCanTransmitAnIncompleteFinalPage() async throws {
    let result = try await Interpreter.render(
      content: """
        << /EndPage { pop pop true } >> setpagedevice
        0 0 moveto 10 0 lineto stroke
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.count == 1)
    if let page = result.output.pages.first {
      #expect(page.effects.count == 2)
    }
  }

  @Test func adaptiveRenderRecordsMixedPageGeometry() async throws {
    let result = try await Interpreter.render(
      content: """
        << /PageSize [100 120] >> setpagedevice showpage
        << /PageSize [200 80] >> setpagedevice showpage
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.map(\.deviceDescriptor.mediaBounds.width) == [100, 200])
    #expect(result.output.pages.map(\.deviceDescriptor.mediaBounds.height) == [120, 80])
  }

  @Test func nullDeviceSuspendsAndRestoresPageMarksAcrossGSave() async throws {
    let result = try await Interpreter.render(
      content: """
        0 0 moveto 10 0 lineto stroke
        gsave nulldevice 0 0 moveto 20 0 lineto stroke grestore
        0 0 moveto 30 0 lineto stroke showpage
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.count == 1)
    #expect(result.output.pages[0].effects.count == 2)
  }

  @Test func zeroCopiesStillClearsThePage() async throws {
    let result = try await Interpreter.render(
      content: """
        << /NumCopies 0 >> setpagedevice
        0 0 moveto 10 0 lineto stroke showpage
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.isEmpty)
  }

  @Test func nullNumCopiesUsesDynamicUserDictionaryValue() async throws {
    let result = try await Interpreter.render(
      content: """
        << /NumCopies null >> setpagedevice
        /#copies 3 def showpage
      """,
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.count == 3)
  }

  @Test func copyPageDoesNotIncrementTheShowPageCount() async throws {
    let result = try await Interpreter.render(
      content: """
        /lastBegin -1 def
        << /BeginPage { /lastBegin exch def } >> setpagedevice
        copypage lastBegin
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(result.output.pages.count == 1)
    #expect(try values[0].value(as: IntegerValue.self).value == 0)
  }
}
