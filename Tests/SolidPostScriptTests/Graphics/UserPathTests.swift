import Testing

@testable import SolidPostScript

@Suite
struct UserPathTests {
  private let square = "{ucache 0 0 10 10 setbbox 0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath}"

  @Test func appendUsesRoundedTranslationAndRestoresTheCTM() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: "0.6 0.6 translate {0 0 10 10 setbbox 0 0 moveto 10 0 lineto} uappend currentpoint",
      count: 2
    )
    #expect(abs(values[0].value - 0.4) < 1e-12)
    #expect(abs(values[1].value - 10.4) < 1e-12)
  }

  @Test func appendKeepsItsBoundingBoxPrivate() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: "-10 -10 moveto {0 0 10 10 setbbox 0 0 moveto 10 10 lineto} uappend 20 20 lineto currentpoint",
      count: 2
    )
    #expect(values.map(\.value) == [20, 20])
  }

  @Test func currentUserPathRoundTripsAndPreservesTrailingMoves() async throws {
    let values = try await Interpreter.results(content: """
      0 0 moveto 10 0 lineto 20 30 moveto
      true upath /p exch def newpath /p load uappend
      /n 0 def {pop pop /n n 1 add def} {pop pop /n n 1 add def}
      {6 {pop} repeat /n n 1 add def} {/n n 1 add def} pathforall
      n /p load 0 get
      """)
    #expect(try values[0].value(as: NameValue.self).value == "ucache")
    #expect(try values[1].value(as: IntegerValue.self).value == 3)
  }

  @Test func emptyPathProducesAValidUserPath() async throws {
    let values = try await Interpreter.results(content: """
      newpath false upath /p exch def
      /p load 0 get /p load 1 get /p load 2 get /p load 3 get /p load 4 get /p load length
      """)
    #expect(try number(values[0]) == 5)
    #expect(try values[1].value(as: NameValue.self).value == "setbbox")
    #expect(try values[2...5].allSatisfy { try number($0) == 0 })
  }

  @Test func userFillAndStrokePreserveGraphicsStateAndRecordIntent() async throws {
    let result = try await Interpreter.render(
      content: """
      1 2 moveto 4 setlinewidth
      \(square) ufill
      \(square) [2 0 0 2 0 0] ustroke
      currentpoint showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(try number(values[0]) == 2)
    #expect(try number(values[1]) == 1)
    let effects = try #require(result.output.pages.first).effects
    guard effects.count == 2 else {
      Issue.record("Expected user fill and stroke effects")
      return
    }
    if case .userPathFill(_, .winding, let state) = effects[0] {
      #expect(state.lineWidth == 4)
    } else {
      Issue.record("Expected user-path fill intent")
    }
    if case .userPathStroke(let outline, _) = effects[1] {
      #expect(!outline.isEmpty)
    } else {
      Issue.record("Expected reduced user-path stroke intent")
    }
  }

  @Test func encodedUserPathPaintsThroughTheSameTypedOperation() async throws {
    let result = try await Interpreter.render(
      content: "[[0 0 10 10 0 0 10 0 10 10 0 10] <000123030A>] ufill showpage",
      to: RecordingGraphicsTarget()
    )
    let effect = try #require(result.output.pages.first?.effects.first)
    guard case .userPathFill(let path, .winding, _) = effect else {
      Issue.record("Expected an encoded user-path fill")
      return
    }
    #expect(!path.isEmpty)
  }

  @Test func userStrokePathReplacesOnlyTheCurrentPath() async throws {
    let values = try await Interpreter.results(content: """
      3 setlinewidth \(square) [2 0 0 2 0 0] ustrokepath
      currentlinewidth pathbbox
      """)
    #expect(try number(values[4]) == 3)
    #expect(try number(values[0]) > 10)
  }

  @Test func cacheReusesTranslationsAndSeparatesLinearTransforms() async throws {
    let result: IntegerValue = try await Interpreter.result(content: """
      /p \(square) def
      /p load ufill 10 20 translate /p load ufill 2 2 scale /p load ufill
      ucachestatus
      /blimit exch def /rmax exch def /rsize exch def
      /bmax exch def /bsize exch def pop
      rsize
      """)
    #expect(result.value == 2)
  }

  @Test func cacheIsSharedSafelyAcrossEnvironmentContexts() async throws {
    let environment = InterpreterEnvironment()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          _ = try await Interpreter.execute(content: "\(square) ufill", environment: environment)
        }
      }
      try await group.waitForAll()
    }
    #expect(environment.userPathCache.status().entries == 1)
  }

  @Test func cacheParametersClampAndRestore() async throws {
    let values = try await Interpreter.results(content: """
      mark (ignored) 1024 setucacheparams
      currentuserparams /MaxUPathItem get
      save mark setucacheparams currentuserparams /MaxUPathItem get exch restore
      currentuserparams /MaxUPathItem get
      """)
    #expect(try number(values[0]) == 1024)
    #expect(try number(values[1]) == Double(UserPathCache.maximumItemBytes))
    #expect(try number(values[2]) == 1024)
  }

  @Test func environmentReportsLiveCacheAndClampedMaximum() async throws {
    let environment = InterpreterEnvironment()
    let values = try await Interpreter.results(
      content: """
      << /MaxUPathCache 100000000 >> setsystemparams
      \(square) ufill
      currentsystemparams /MaxUPathCache get
      currentsystemparams /CurUPathCache get
      """,
      environment: environment
    )
    #expect(try number(values[0]) > 0)
    #expect(try number(values[1]) == Double(UserPathCache.maximumBytes))
  }

  @Test func ucacheOutsideAUserPathIsANoOp() async throws {
    let value: IntegerValue = try await Interpreter.result(content: "1 ucache")
    #expect(value.value == 1)
  }

  @Test func malformedUserPathPaintingRollsBackOperands() async throws {
    let values = try await Interpreter.results(content: """
      /bad {0 0 1 1 setbbox 0 0 rmoveto} def
      {/bad load ufill} stopped $error /errorname get
      """)
    #expect(try values[0].value(as: NameValue.self).value == "typecheck")
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(values[2].type == .operator)
    #expect(values[3].isProcedure)
  }

  @Test func literalOperatorNamesAreRejected() async throws {
    let error: NameValue = try await Interpreter.result(
      content: "{[0 0 1 1 /setbbox] ufill} stopped $error /errorname get"
    )
    #expect(error.value == "typecheck")
  }
}

private func number(_ object: Object) throws -> Double {
  guard let value = object.value as? NumericConvertible else { throw Error.typeCheck }
  return value.real
}
