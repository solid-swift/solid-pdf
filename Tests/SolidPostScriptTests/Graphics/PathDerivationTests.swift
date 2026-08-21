import Testing

@testable import SolidPostScript

@Suite
struct PathDerivationTests {
  @Test func flatnessStrokeAdjustmentAndInitMatrixRoundTrip() async throws {
    let values = try await Interpreter.results(content: """
      2 setflat true setstrokeadjust
      3 4 translate initmatrix matrix currentmatrix
      currentstrokeadjust currentflat
      """)
    #expect(try number(values[0]) == 2)
    #expect(try values[1].value(as: BooleanValue.self).value)
    let matrix = try values[2].value(as: ArrayValue.self).objects(in: 0..<6)
    #expect(try matrix.map(Operators.numeric) == [1, 0, 0, 1, 0, 0])
  }

  @Test(arguments: [0.01, 0.2, 100.0, 1000.0])
  func setFlatClampsWithoutError(_ supplied: Double) async throws {
    let result: RealValue = try await Interpreter.result(content: "\(supplied) setflat currentflat")
    #expect(result.value == min(100, max(0.2, supplied)))
  }

  @Test func pathBoundingBoxUsesControlPointsAndIgnoresTrailingMove() async throws {
    let values: [RealValue] = try await Interpreter.result(
      content: "0 0 moveto 2 8 8 8 10 0 curveto 100 100 moveto pathbbox",
      count: 4
    )
    #expect(values.map(\.value).reversed() == [0, 0, 10, 8])
  }

  @Test func explicitBoundingBoxTakesPrecedenceAndConstrainsCoordinates() async throws {
    let values = try await Interpreter.results(content: """
      0 0 10 20 setbbox 2 3 moveto pathbbox
      {11 3 lineto} stopped $error /errorname get
      """)
    #expect(try values[0].value(as: NameValue.self).value == "rangecheck")
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(values[2].type == .operator)
    #expect(try number(values[3]) == 3)
    #expect(try number(values[4]) == 11)
    #expect(try number(values[5]) == 20)
    #expect(try number(values[8]) == 0)
  }

  @Test func pathForAllSnapshotsPathAndActsAsLoop() async throws {
    let count: IntegerValue = try await Interpreter.result(content: """
      /n 0 def
      0 0 moveto 10 0 lineto 10 10 20 10 20 20 curveto closepath
      {pop pop /n n 1 add def newpath}
      {pop pop /n n 1 add def}
      {6 {pop} repeat /n n 1 add def}
      {/n n 1 add def}
      pathforall n
      """)
    #expect(count.value == 4)

    let exited: IntegerValue = try await Interpreter.result(content: """
      /n 0 def 0 0 moveto 1 0 lineto 2 0 lineto
      {pop pop /n n 1 add def exit} {pop pop} {6 {pop} repeat} {} pathforall n
      """)
    #expect(exited.value == 1)
  }

  @Test func derivedPathsReplaceTheCurrentPath() async throws {
    let values = try await Interpreter.results(content: """
      0 0 moveto 0 10 10 10 10 0 curveto flattenpath
      /curves 0 def {pop pop} {pop pop} {6 {pop} repeat /curves curves 1 add def} {} pathforall curves
      reversepath currentpoint
      2 setlinewidth strokepath pathbbox
      """)
    #expect(try number(values[6]) == 0)
    #expect(values.count == 7)
  }

  @Test func clippingPathAndClipStackUseResolvedGeometry() async throws {
    let count: IntegerValue = try await Interpreter.result(content: """
      clipsave
      0 0 20 20 rectclip 5 5 5 5 rectclip
      clippath /n 0 def
      {pop pop /n n 1 add def} {pop pop /n n 1 add def}
      {6 {pop} repeat /n n 1 add def} {/n n 1 add def} pathforall
      cliprestore n
      """)
    #expect(count.value > 0)
  }

  @Test func initGraphicsPreservesFlatnessStrokeAdjustmentAndClipStack() async throws {
    let values = try await Interpreter.results(content: """
      3 setflat true setstrokeadjust clipsave initgraphics cliprestore
      currentflat currentstrokeadjust
      """)
    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try number(values[1]) == 3)
  }
}

private func number(_ object: Object) throws -> Double {
  guard let value = object.value as? NumericConvertible else { throw Error.typeCheck }
  return value.real
}
