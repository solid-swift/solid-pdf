import Testing

@testable import SolidPostScript

@Suite struct FormTests {
  @Test func formTypeOneIsAnImplicitResource() async throws {
    let value: IntegerValue = try await Interpreter.result(content: "1 /FormType findresource")
    #expect(value.value == 1)
  }

  @Test func formResourcesUseTypeSpecificValidation() async throws {
    let error: NameValue = try await Interpreter.result(content: """
      { << /FormType 2 /BBox [0 0 10 10] /Matrix matrix /PaintProc {} >>
        /Bad /Form defineresource pop
      } stopped
      $error /errorname get
      """)
    #expect(error.value == "typecheck")
  }

  @Test func formCacheParametersUseAchievableLimits() async throws {
    let context = try await Interpreter.execute(content: """
      << /MaxFormCache 2147483647 >> setsystemparams
      << /MaxFormItem 2147483647 >> setuserparams
      currentsystemparams /MaxFormCache get
      currentuserparams /MaxFormItem get
      currentsystemparams /CurFormCache get
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: IntegerValue.self).value == 64 * 1024 * 1024)
    #expect(try values[1].value(as: IntegerValue.self).value == 8 * 1024 * 1024)
    #expect(try values[0].value(as: IntegerValue.self).value == 0)
  }

  @Test func graphicsFormRetainsSemanticNestedDisplayList() {
    let state = GraphicsCanonicalState.initial(for: .letter).snapshot
    let nested = GraphicsForm(
      bounds: GraphicsRect(x: 0, y: 0, width: 1, height: 1),
      matrix: .identity,
      deviceDescriptor: .letter,
      compilationState: state,
      displayList: GraphicsDisplayList(effects: [.erase(state: state)])
    )
    let list = GraphicsDisplayList(effects: [.form(nested, state: state)])
    #expect(list.effects.count == 1)
    #expect(list.checkedFootprint() > 0)
  }

  @Test func execformInitializesOnceAndCachesItsDisplayList() async throws {
    let context = try await Interpreter.execute(content: """
      /painted 0 def
      /f << /FormType 1 /BBox [0 0 10 10] /Matrix matrix
        /Implementation (forged)
        /PaintProc { pop /painted painted 1 add store 0 0 10 10 rectfill }
      >> def
      f execform f execform
      painted f rcheck f /Implementation get rcheck
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: IntegerValue.self).value == 1)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: BooleanValue.self).value == false)
  }

  @Test func execformRestoresTheCallerGraphicsStateAndPath() async throws {
    let context = try await Interpreter.execute(content: """
      0.25 setgray 3 4 moveto
      << /FormType 1 /BBox [0 0 5 5] /Matrix [2 0 0 2 10 20]
         /PaintProc { pop 0.75 setgray newpath 1 1 moveto 2 2 lineto stroke }
      >> execform
      currentpoint currentgray
      """)
    let values = try await context.results()
    #expect(try values[2].value(as: RealValue.self).value == 3)
    #expect(try values[1].value(as: RealValue.self).value == 4)
    #expect(try values[0].value(as: RealValue.self).value == 0.25)
  }

  @Test func execformRejectsPageTransmissionAndRecursion() async throws {
    let pageError: NameValue = try await Interpreter.result(content: """
      { << /FormType 1 /BBox [0 0 1 1] /Matrix matrix
           /PaintProc { pop showpage } >> execform } stopped
      $error /errorname get
      """)
    #expect(pageError.value == "undefined")

    let recursionError: NameValue = try await Interpreter.result(content: """
      /f << /FormType 1 /BBox [0 0 1 1] /Matrix matrix
        /PaintProc { execform } >> def
      { f execform } stopped $error /errorname get
      """)
    #expect(recursionError.value == "limitcheck")
  }

  @Test func execformValidationUsesThePublicOperatorAsTheCommand() async throws {
    let context = try await Interpreter.execute(content: """
      { << /FormType 2 /BBox [0 0 1 1] /Matrix matrix /PaintProc {} >> execform } stopped
      $error /errorname get $error /command get /execform load eq
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: NameValue.self).value == "rangecheck")
    #expect(try values[0].value(as: BooleanValue.self).value)
  }

  @Test func paintProcErrorsKeepTheirFailingCommand() async throws {
    let context = try await Interpreter.execute(content: """
      { << /FormType 1 /BBox [0 0 1 1] /Matrix matrix
           /PaintProc { pop doesnotexist } >> execform } stopped
      $error /errorname get $error /command get
      """)
    let values = try await context.results()
    #expect(try values[1].value(as: NameValue.self).value == "undefined")
    #expect(try values[0].value(as: NameValue.self).value == "doesnotexist")
  }
}
