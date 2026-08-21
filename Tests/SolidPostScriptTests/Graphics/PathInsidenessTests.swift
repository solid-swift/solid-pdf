import Testing

@testable import SolidPostScript

@Suite
struct PathInsidenessTests {
  private let square = "{0 0 10 10 setbbox 0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath}"

  @Test func fillInsidenessUsesPixelCoverageAndIgnoresClipping() async throws {
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      100 100 1 1 rectclip
      0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath
      5 5 infill 20 20 infill
      """,
      count: 2
    )
    #expect(values.map(\.value) == [false, true])
  }

  @Test func evenOddInsidenessExcludesNestedInterior() async throws {
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      0 0 10 10 rectclip initclip
      0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath
      2 2 moveto 8 2 lineto 8 8 lineto 2 8 lineto closepath
      5 5 ineofill 1 1 ineofill
      """,
      count: 2
    )
    #expect(values.map(\.value) == [true, false])
  }

  @Test func apertureFormsAlwaysUseWindingForTheAperture() async throws {
    let aperture = "{0 0 10 10 setbbox 1 1 moveto 3 1 lineto 3 3 lineto 1 3 lineto closepath}"
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      0 0 moveto 2 0 lineto 2 2 lineto 0 2 lineto closepath
      \(aperture) infill
      \(aperture) ineofill
      """,
      count: 2
    )
    #expect(values.map(\.value) == [true, true])
  }

  @Test func strokeInsidenessUsesLineAndDashState() async throws {
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      4 setlinewidth [4 4] 0 setdash 0 0 moveto 20 0 lineto
      1 0 instroke 6 0 instroke 1 4 instroke
      """,
      count: 3
    )
    #expect(values.map(\.value) == [false, false, true])
  }

  @Test func ordinaryAndEncodedUserPathsProduceEquivalentTests() async throws {
    let encoded = "[[0 0 10 10 0 0 10 0 10 10 0 10] <000123030a>]"
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      5 5 \(square) inufill
      5 5 \(encoded) inufill
      20 20 \(encoded) inufill
      """,
      count: 3
    )
    #expect(values.map(\.value) == [false, true, true])
  }

  @Test func userPathApertureAndOptionalStrokeMatrixFormsWork() async throws {
    let aperture = "{0 0 2 2 setbbox 0 0 moveto 2 0 lineto 2 2 lineto 0 2 lineto closepath}"
    let values: [BooleanValue] = try await Interpreter.result(
      content: """
      \(aperture) \(square) inufill
      1 setlinewidth 1 0 \(square) inustroke
      1 0 \(square) [2 0 0 2 0 0] inustroke
      \(aperture) \(square) [2 0 0 2 0 0] inustroke
      """,
      count: 4
    )
    #expect(values.map(\.value) == [true, true, true, true])
  }

  @Test func insidenessLeavesTheCurrentPathUnchanged() async throws {
    let values = try await Interpreter.results(content: """
      1 2 moveto 3 4 lineto 2 3 infill currentpoint
      """)
    #expect(try number(values[0]) == 4)
    #expect(try number(values[1]) == 3)
    #expect(try !values[2].value(as: BooleanValue.self).value)
  }

  @Test(arguments: [
    "{0 0 1 1 setbbox 0 0 rmoveto}",
    "{0 0 1 1 setbbox 0 0 moveto 1}",
    "{0 0 1 1 setbbox 0 0 moveto pop}",
    "[[0 0 1 1] <ff>]",
    "[[0 0 1 1] <00ff>]",
  ])
  func malformedUserPathsRaiseTypeCheck(_ userPath: String) async throws {
    let error: NameValue = try await Interpreter.result(
      content: "{5 5 \(userPath) inufill} stopped $error /errorname get"
    )
    #expect(error.value == "typecheck")
  }

  @Test func inaccessibleUserPathRaisesInvalidAccess() async throws {
    let error: NameValue = try await Interpreter.result(
      content: "{5 5 \(square) cvlit noaccess inufill} stopped $error /errorname get"
    )
    #expect(error.value == "invalidaccess")
  }
}

private func number(_ object: Object) throws -> Double {
  guard let value = object.value as? NumericConvertible else { throw Error.typeCheck }
  return value.real
}
