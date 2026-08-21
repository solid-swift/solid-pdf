import Testing

@testable import SolidPostScript

@Suite
struct TrappingTests {
  @Test func trappingProcSetAndTypeResourceAreAvailable() async throws {
    let values = try await Interpreter.results(content: """
      1001 /TrappingType resourcestatus { pop pop true } { false } ifelse
      /Trapping /ProcSet findresource dup /settrapparams known exch /settrapzone known
      """)

    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[2].value(as: BooleanValue.self).value)
  }

  @Test func trapParametersMergeClampAndReturnIndependentDictionaries() async throws {
    let result = try await Interpreter.render(
      content: """
        /Trapping /ProcSet findresource begin
        << /Trapping true >> setpagedevice
        << /TrapWidth 20 /StepLimit .25 /TrapSetName (production) >> settrapparams
        currenttrapparams dup /StepLimit .75 put pop
        currenttrapparams dup /TrapWidth get exch /StepLimit get
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: RealValue.self).value == 0.25)
    #expect(try values[1].value(as: RealValue.self).value == 10)
  }

  @Test func trappingStateIgnoresGSaveButParticipatesInLanguageRestore() async throws {
    let values = try await Interpreter.results(content: """
      /trappingOps /Trapping /ProcSet findresource def
      << /Trapping true >> setpagedevice
      { gsave << /TrapWidth 2 >> trappingOps /settrapparams get exec grestore
        trappingOps /currenttrapparams get exec /TrapWidth get
      } stopped
      """)

    #expect(try !values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: RealValue.self).value == 2)

    let restored = try await Interpreter.results(content: """
      /trappingOps /Trapping /ProcSet findresource def
      << /Trapping true >> setpagedevice
      << /TrapWidth 2 >> trappingOps /settrapparams get exec
      /doRestore { saved restore } bind def
      save /saved exch def
      << /TrapWidth 3 >> trappingOps /settrapparams get exec
      doRestore
      trappingOps /currenttrapparams get exec /TrapWidth get
      """)
    #expect(try restored[0].value(as: RealValue.self).value == 2)

  }

  @Test func setTrapZoneClearsPathAndRecordingPreservesZone() async throws {
    let result = try await Interpreter.render(
      content: """
        /Trapping /ProcSet findresource begin
        << /Trapping true >> setpagedevice
        newpath 0 0 moveto 20 0 lineto 20 20 lineto closepath settrapzone
        { currentpoint } stopped
        showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()

    #expect(try values[0].value(as: BooleanValue.self).value)
    let page = try #require(result.output.pages.first)
    #expect(page.trapping.enabled)
    #expect(page.trapping.zones.count == 1)
  }

  @Test func malformedAndEncapsulatedUpdatesUsePostScriptErrors() async throws {
    let values = try await Interpreter.results(content: """
      /Trapping /ProcSet findresource begin
      << /Trapping true >> setpagedevice
      { << /StepLimit 2 >> settrapparams } stopped $error /errorname get
      """)

    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: NameValue.self).value == "rangecheck")
  }
}
