import Foundation

extension Operators {
  static func validateFormDictionary(_ dictionary: DictionaryValue) throws {
    let formType = try dictionary.objectValue(forKey: "FormType", as: IntegerValue.self).value
    guard formType == 1 else { throw Error.rangeCheck }

    let bounds = try numericArray(dictionary.object(forKey: "BBox"))
    guard bounds.count == 4,
      bounds.allSatisfy(\.isFinite),
      bounds[0] <= bounds[2],
      bounds[1] <= bounds[3]
    else { throw Error.rangeCheck }

    _ = try readMatrix(dictionary.object(forKey: "Matrix"))
    try dictionary.object(forKey: "PaintProc").checkProcedure()
    if let xuid = try dictionary.object(forKeyIfExists: "XUID") {
      _ = try arrayObjects(xuid).map { try $0.value(as: IntegerValue.self) }
    }
  }
}
