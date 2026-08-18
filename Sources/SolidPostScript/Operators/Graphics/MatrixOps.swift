import Foundation

extension Operators {

  static let matrixOps: [OperatorValue] = [
    MakeMatrix.instance,
    InitializeMatrix.instance,
    IdentityMatrix.instance,
    DefaultMatrix.instance,
    CurrentMatrix.instance,
    SetMatrix.instance,
    Translate.instance,
    Scale.instance,
    Rotate.instance,
    Concatenate.instance,
    ConcatenateMatrix.instance,
    Transform.instance,
    DistanceTransform.instance,
    InverseTransform.instance,
    InverseDistanceTransform.instance,
    InvertMatrix.instance,
  ]

  enum MakeMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["matrix"]

    func execute(context: isolated Context) async throws {
      context.operands.push(try makeMatrixObject(.identity, context: context))
    }
  }

  enum InitializeMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["initmatrix"]

    func execute(context: isolated Context) async throws {
      let matrix = context.graphicsDeviceDescriptor.defaultMatrix
      try context.applyGraphicsOperation(.transform(.setMatrix(matrix))) { $0.matrix = matrix }
    }
  }

  enum IdentityMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["identmatrix"]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      try writeMatrix(.identity, to: object)
      context.operands.push(object)
    }
  }

  enum DefaultMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["defaultmatrix"]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      try writeMatrix(context.graphicsDeviceDescriptor.defaultMatrix, to: object)
      context.operands.push(object)
    }
  }

  enum CurrentMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentmatrix"]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      try writeMatrix(context.graphicsState.matrix, to: object)
      context.operands.push(object)
    }
  }

  enum SetMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setmatrix"]

    func execute(context: isolated Context) async throws {
      let matrix = try readMatrix(context.operands.pop())
      try context.applyGraphicsOperation(.transform(.setMatrix(matrix))) { $0.matrix = matrix }
    }
  }

  enum Translate: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["translate"]

    func execute(context: isolated Context) async throws {
      if try context.operands.peek().type == .array {
        let destination = try context.operands.pop()
        let operands = try context.operands.pop(count: 2)
        let y = try numeric(operands[0])
        let x = try numeric(operands[1])
        try writeMatrix(GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y), to: destination)
        context.operands.push(destination)
      } else {
        let operands = try context.operands.pop(count: 2)
        let y = try numeric(operands[0])
        let x = try numeric(operands[1])
        let matrix = GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
        try context.applyGraphicsOperation(.transform(.translate(x: x, y: y))) {
          $0.matrix = matrix.concatenated(with: $0.matrix)
        }
      }
    }
  }

  enum Scale: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["scale"]

    func execute(context: isolated Context) async throws {
      if try context.operands.peek().type == .array {
        let destination = try context.operands.pop()
        let operands = try context.operands.pop(count: 2)
        let y = try numeric(operands[0])
        let x = try numeric(operands[1])
        try writeMatrix(GraphicsMatrix(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0), to: destination)
        context.operands.push(destination)
      } else {
        let operands = try context.operands.pop(count: 2)
        let y = try numeric(operands[0])
        let x = try numeric(operands[1])
        let matrix = GraphicsMatrix(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
        try context.applyGraphicsOperation(.transform(.scale(x: x, y: y))) {
          $0.matrix = matrix.concatenated(with: $0.matrix)
        }
      }
    }
  }

  enum Rotate: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rotate"]

    func execute(context: isolated Context) async throws {
      if try context.operands.peek().type == .array {
        let destination = try context.operands.pop()
        let degrees = try numeric(context.operands.pop())
        try writeMatrix(rotation(degrees), to: destination)
        context.operands.push(destination)
      } else {
        let degrees = try numeric(context.operands.pop())
        let matrix = rotation(degrees)
        try context.applyGraphicsOperation(.transform(.rotate(degrees: degrees))) {
          $0.matrix = matrix.concatenated(with: $0.matrix)
        }
      }
    }
  }

  enum Concatenate: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["concat"]

    func execute(context: isolated Context) async throws {
      let matrix = try readMatrix(context.operands.pop())
      try context.applyGraphicsOperation(.transform(.concatenate(matrix))) {
        $0.matrix = matrix.concatenated(with: $0.matrix)
      }
    }
  }

  enum ConcatenateMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["concatmatrix"]

    func execute(context: isolated Context) async throws {
      let destination = try context.operands.pop()
      let second = try readMatrix(context.operands.pop())
      let first = try readMatrix(context.operands.pop())
      try writeMatrix(first.concatenated(with: second), to: destination)
      context.operands.push(destination)
    }
  }

  enum Transform: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["transform"]

    func execute(context: isolated Context) async throws {
      try transformPoint(context: context, distance: false, inverse: false)
    }
  }

  enum DistanceTransform: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["dtransform"]

    func execute(context: isolated Context) async throws {
      try transformPoint(context: context, distance: true, inverse: false)
    }
  }

  enum InverseTransform: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["itransform"]

    func execute(context: isolated Context) async throws {
      try transformPoint(context: context, distance: false, inverse: true)
    }
  }

  enum InverseDistanceTransform: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["idtransform"]

    func execute(context: isolated Context) async throws {
      try transformPoint(context: context, distance: true, inverse: true)
    }
  }

  enum InvertMatrix: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["invertmatrix"]

    func execute(context: isolated Context) async throws {
      let destination = try context.operands.pop()
      let source = try readMatrix(context.operands.pop())
      guard let inverse = source.inverted else { throw Error.undefinedResult }
      try writeMatrix(inverse, to: destination)
      context.operands.push(destination)
    }
  }

  static func readMatrix(_ object: Object) throws -> GraphicsMatrix {
    let array = try object.value(as: ArrayValue.self)
    guard array.count == 6 else { throw Error.rangeCheck }
    let values = try array.objects(in: array.range).map(numeric)
    return GraphicsMatrix(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
  }

  static func writeMatrix(_ matrix: GraphicsMatrix, to object: Object) throws {
    let array = try object.value(as: ArrayValue.self)
    guard array.count == 6 else { throw Error.rangeCheck }
    try array.updateObjects(
      [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].map { try Object.real($0) },
      startingAt: 0
    )
  }

  static func makeMatrixObject(_ matrix: GraphicsMatrix, context: isolated Context) throws -> Object {
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: 6, objectType: .array))
    let object = try Object.array(
      [matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].map { try Object.real($0) },
      access: .unlimited,
      vm: context.allocationMode,
      kind: .literal
    )
    try context.adopt(object)
    return object
  }

  static func transformPoint(context: isolated Context, distance: Bool, inverse: Bool) throws {
    let matrix: GraphicsMatrix
    if try context.operands.peek().type == .array {
      matrix = try readMatrix(context.operands.pop())
    } else {
      matrix = context.graphicsState.matrix
    }
    let operands = try context.operands.pop(count: 2)
    let point = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
    let effective: GraphicsMatrix
    if inverse {
      guard let inverted = matrix.inverted else { throw Error.undefinedResult }
      effective = inverted
    } else {
      effective = matrix
    }
    let result = distance ? effective.transformDistance(point) : effective.transform(point)
    context.operands.push(try .real(result.y), try .real(result.x))
  }

  static func rotation(_ degrees: Double) -> GraphicsMatrix {
    let radians = degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
    let cosine = cos(radians)
    let sine = sin(radians)
    return GraphicsMatrix(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
  }
}
