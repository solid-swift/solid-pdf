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
}
