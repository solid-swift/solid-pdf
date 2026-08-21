import Foundation

struct FormDefinition {
  let bounds: GraphicsRect
  let matrix: GraphicsMatrix
  let paintProcedure: Object
  let paintProcedureIdentity: ObjectIdentifier
  let paintProcedureRevision: UInt64
  let xuid: [Int32]?
}

extension Operators {
  static func validateFormDictionary(_ dictionary: DictionaryValue) throws {
    _ = try formDefinition(dictionary)
  }

  static func formDefinition(_ dictionary: DictionaryValue) throws -> FormDefinition {
    let formType = try dictionary.objectValue(forKey: "FormType", as: IntegerValue.self).value
    guard formType == 1 else { throw Error.rangeCheck }

    let values = try numericArray(dictionary.object(forKey: "BBox"))
    guard values.count == 4,
      values.allSatisfy(\.isFinite),
      values[0] <= values[2],
      values[1] <= values[3]
    else { throw Error.rangeCheck }

    let matrix = try readMatrix(dictionary.object(forKey: "Matrix"))
    let paintProcedure = try dictionary.object(forKey: "PaintProc")
    try paintProcedure.checkProcedure()
    let procedureIdentity: ObjectIdentifier
    let procedureRevision: UInt64
    switch paintProcedure.value {
    case let array as ArrayValue:
      procedureIdentity = array.allocation.identity
      procedureRevision = array.revision
    case let array as PackedArrayValue:
      procedureIdentity = array.allocation.identity
      procedureRevision = array.revision
    default:
      preconditionFailure("checkProcedure accepted an unsupported value")
    }
    let xuid = try dictionary.object(forKeyIfExists: "XUID").map {
      try arrayObjects($0).map { try $0.value(as: IntegerValue.self).value }
    }
    return FormDefinition(
      bounds: GraphicsRect(
        x: values[0],
        y: values[1],
        width: values[2] - values[0],
        height: values[3] - values[1]
      ),
      matrix: matrix,
      paintProcedure: paintProcedure,
      paintProcedureIdentity: procedureIdentity,
      paintProcedureRevision: procedureRevision,
      xuid: xuid
    )
  }
}
