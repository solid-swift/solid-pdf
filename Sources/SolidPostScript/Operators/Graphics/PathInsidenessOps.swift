import Foundation
import SolidRaster

extension Operators {
  static let pathInsidenessOps: [OperatorValue] = [
    InFill.instance,
    InEvenOddFill.instance,
    InStroke.instance,
    InUserFill.instance,
    InUserEvenOddFill.instance,
    InUserStroke.instance,
  ]

  enum InFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["infill"]

    func execute(context: isolated Context) async throws {
      let aperture = try aperture(context: context)
      let target = try GraphicsPathGeometry.region(
        for: context.graphicsState.path,
        rule: .winding,
        flatness: context.graphicsState.flatness
      )
      context.operands.push(.boolean(target.intersects(aperture)))
    }
  }

  enum InEvenOddFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ineofill"]

    func execute(context: isolated Context) async throws {
      let aperture = try aperture(context: context)
      let target = try GraphicsPathGeometry.region(
        for: context.graphicsState.path,
        rule: .evenOdd,
        flatness: context.graphicsState.flatness
      )
      context.operands.push(.boolean(target.intersects(aperture)))
    }
  }

  enum InStroke: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["instroke"]

    func execute(context: isolated Context) async throws {
      let aperture = try aperture(context: context)
      let outline = try GraphicsPathGeometry.strokeOutline(
        path: context.graphicsState.path,
        state: context.graphicsState
      )
      let target = try GraphicsPathGeometry.region(
        for: outline,
        rule: .winding,
        flatness: context.graphicsState.flatness
      )
      context.operands.push(.boolean(target.intersects(aperture)))
    }
  }

  enum InUserFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["inufill"]

    func execute(context: isolated Context) async throws {
      try testUserFill(context: context, rule: .winding)
    }
  }

  enum InUserEvenOddFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["inueofill"]

    func execute(context: isolated Context) async throws {
      try testUserFill(context: context, rule: .evenOdd)
    }
  }

  enum InUserStroke: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["inustroke"]

    func execute(context: isolated Context) async throws {
      let optionalMatrix: GraphicsMatrix?
      if try isMatrix(context.operands.peek()) {
        optionalMatrix = try readMatrix(context.operands.pop())
      } else {
        optionalMatrix = nil
      }
      let targetDefinition = try UserPathDecoder.decode(context.operands.pop())
      let aperture = try aperture(context: context)
      let path = try targetDefinition.materialized(
        matrix: context.graphicsState.matrix,
        roundTranslation: true
      )
      let strokeMatrix = optionalMatrix?.concatenated(with: context.graphicsState.matrix)
        ?? context.graphicsState.matrix
      guard strokeMatrix.inverted != nil else { throw Error.undefinedResult }
      let outline = try GraphicsPathGeometry.strokeOutline(
        path: path,
        state: context.graphicsState,
        matrix: strokeMatrix
      )
      let target = try GraphicsPathGeometry.region(
        for: outline,
        rule: .winding,
        flatness: context.graphicsState.flatness
      )
      context.operands.push(.boolean(target.intersects(aperture)))
    }
  }

  private static func testUserFill(
    context: isolated Context,
    rule: GraphicsFillRule
  ) throws {
    let definition = try UserPathDecoder.decode(context.operands.pop())
    let aperture = try aperture(context: context)
    let path = try definition.materialized(matrix: context.graphicsState.matrix, roundTranslation: true)
    let target = try GraphicsPathGeometry.region(
      for: path,
      rule: rule,
      flatness: context.graphicsState.flatness
    )
    context.operands.push(.boolean(target.intersects(aperture)))
  }

  private static func aperture(context: isolated Context) throws -> RasterRegion {
    if (try context.operands.peek()).value is NumericConvertible {
      let operands = try context.operands.pop(count: 2)
      let point = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      let device = context.graphicsState.matrix.transform(point)
      do {
        return try RasterRegion.rectangle(RasterRect(
          x: floor(device.x),
          y: floor(device.y),
          width: 1,
          height: 1
        ))
      } catch {
        throw error.postScriptError
      }
    }
    let definition = try UserPathDecoder.decode(context.operands.pop())
    let path = try definition.materialized(matrix: context.graphicsState.matrix, roundTranslation: true)
    return try GraphicsPathGeometry.region(
      for: path,
      rule: .winding,
      flatness: context.graphicsState.flatness
    )
  }

  private static func isMatrix(_ object: Object) throws -> Bool {
    guard let array = object.value as? ArrayValue else { return false }
    try array.access.check(.read)
    return array.count == 6
  }
}
