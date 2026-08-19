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
}
