import Testing

@testable import SolidPostScript

@Suite
struct HalftoneTests {
  @Test func screenCompatibilityOperatorsPreserveTheInstalledProcedures() async throws {
    let values = try await Interpreter.results(content: """
      /spot {add 2 div} bind def
      60 45 /spot load setscreen
      currentscreen /spot load eq exch 45 eq and exch 72 eq and
      currenthalftone /HalftoneType get 1 eq
      10 15 /spot load 20 30 /spot load 40 45 /spot load 50 60 /spot load setcolorscreen
      currenthalftone /HalftoneType get 2 eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func thresholdAndColorantHalftonesAreInstalledTransactionally() async throws {
    let values = try await Interpreter.results(content: """
      /one << /HalftoneType 3 /Width 2 /Height 2 /Thresholds <0080c040> >> def
      one sethalftone currenthalftone one eq /oneOK exch def
      /many << /HalftoneType 5
        /Default << /HalftoneType 3 /Width 1 /Height 1 /Thresholds <00> >>
        /Spot << /HalftoneType 3 /Width 1 /Height 1 /Thresholds <ff> /TransferFunction {} >>
      >> def
      many sethalftone currenthalftone many eq /manyOK exch def
      { << /HalftoneType 3 /Width 2 /Height 2 /Thresholds <00> >> sethalftone } stopped pop clear
      oneOK manyOK
      $error /errorname get /rangecheck eq
      currenthalftone many eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func halftoneStateParticipatesInGraphicsAndLanguageSave() async throws {
    let values = try await Interpreter.results(content: """
      /first << /HalftoneType 3 /Width 1 /Height 1 /Thresholds <20> >> def
      /second << /HalftoneType 3 /Width 1 /Height 1 /Thresholds <e0> >> def
      first sethalftone
      gsave second sethalftone grestore currenthalftone first eq
      save second sethalftone restore currenthalftone first eq
      gstate second sethalftone setgstate currenthalftone first eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func halftoneResourcesAdvertiseOnlyStandardTypes() async throws {
    let values = try await Interpreter.results(content: """
      1 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      2 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      3 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      4 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      5 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      6 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      10 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      16 /HalftoneType resourcestatus {pop pop true} {false} ifelse
      9 /HalftoneType resourcestatus
      """)

    #expect(try values[0].value(as: BooleanValue.self).value == false)
    #expect(try values.dropFirst().allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func spotProceduresRequireOneBalancedNumericResult() async throws {
    let values = try await Interpreter.results(content: """
      { 60 0 {dup} setscreen } stopped pop clear
      $error /errorname get /typecheck eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func dictionariesReportActualScreensAndCompatibilityOverridesCopies() async throws {
    let values = try await Interpreter.results(content: """
      /spot {add 2 div} bind def
      /measured << /HalftoneType 1 /Frequency 60 /Angle 30 /SpotFunction /spot load
        /ActualFrequency 0 /ActualAngle 0 >> def
      measured sethalftone
      measured /ActualFrequency get 72 eq
      measured /ActualAngle get 30 eq
      /prototype << /HalftoneType 1 /Frequency 10 /Angle 20 /SpotFunction /spot load >> readonly def
      60 45 prototype setscreen
      currenthalftone /Frequency get 60 eq
      currenthalftone /Angle get 45 eq
      prototype /Frequency get 10 eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func fileThresholdsConsumeExactlyAndCurrentFilesAreCircular() async throws {
    let values = try await Interpreter.results(content: """
      /source <0102> /ReusableStreamDecode filter def
      << /HalftoneType 6 /Width 1 /Height 1 /Thresholds source >> sethalftone
      source read 2 eq exch pop
      currenthalftone /Thresholds get /thresholds exch def
      thresholds read 1 eq exch pop
      thresholds read 1 eq exch pop
      /source16 <0102> /ReusableStreamDecode filter def
      << /HalftoneType 16 /Width 1 /Height 1 /Thresholds source16 >> sethalftone
      currenthalftone dup /Thresholds get rcheck not
      exch sethalftone currenthalftone /HalftoneType get 16 eq
      """)

    for (index, value) in values.enumerated() {
      #expect(try value.value(as: BooleanValue.self).value, "Result \(index) should be true")
    }
  }

  @Test func colorAndAngledThresholdDictionariesSupportEveryStandardShape() async throws {
    let values = try await Interpreter.results(content: """
      /color << /HalftoneType 4
        /RedWidth 1 /RedHeight 1 /RedThresholds <10>
        /GreenWidth 1 /GreenHeight 1 /GreenThresholds <20>
        /BlueWidth 1 /BlueHeight 1 /BlueThresholds <30>
        /GrayWidth 1 /GrayHeight 1 /GrayThresholds <40>
      >> def
      color sethalftone currenthalftone color eq
      /angled << /HalftoneType 10 /Xsquare 1 /Ysquare 2 /Thresholds <0010203040> >> def
      angled sethalftone currenthalftone angled eq
      """)

    #expect(try values.allSatisfy { try $0.value(as: BooleanValue.self).value })
  }

  @Test func screenManagerIsSafeAcrossConcurrentContexts() async throws {
    let environment = InterpreterEnvironment()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for angle in stride(from: 0, to: 360, by: 45) {
        group.addTask {
          _ = try await Interpreter.execute(
            content: "60 \(angle) {add 2 div} setscreen",
            environment: environment
          )
        }
      }
      try await group.waitForAll()
    }
    #expect(environment.screenManager.status().cachedBytes > 0)
  }
}
