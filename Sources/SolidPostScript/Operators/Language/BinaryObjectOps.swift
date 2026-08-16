import Foundation

extension Operators {
  static let binaryObjectOps: [OperatorValue] = [
    SetObjectFormat.instance,
    CurrentObjectFormat.instance,
    PrintObject.instance,
    WriteObject.instance,
  ]

  /// Implements the PostScript `setobjectformat` operator.
  public enum SetObjectFormat: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setobjectformat"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let value: IntegerValue = try context.operands.popAs()
      context.objectFormat = try ObjectFormat(validating: value.value)
    }
  }

  /// Implements the PostScript `currentobjectformat` operator.
  public enum CurrentObjectFormat: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentobjectformat"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      context.operands.push(.integer(context.objectFormat.rawValue))
    }
  }

  /// Implements the PostScript `printobject` operator.
  public enum PrintObject: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["printobject"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let (tagObject, object) = try context.operands.pop2()
      let tag = try Operators.validatedTag(tagObject)
      var encoder = BinaryObjectSequenceEncoder(format: context.objectFormat, tag: tag)
      let data = try encoder.encode(object)
      try context.standardOutput().write(contentsOf: data, context: context)
    }
  }

  /// Implements the PostScript `writeobject` operator.
  public enum WriteObject: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["writeobject"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let (tagObject, object, fileObject) = try context.operands.pop3()
      let tag = try Operators.validatedTag(tagObject)
      let file = try fileObject.value(as: FileValue.self)
      try file.checkWritable()

      var encoder = BinaryObjectSequenceEncoder(format: context.objectFormat, tag: tag)
      let data = try encoder.encode(object)
      try file.file.write(contentsOf: data, context: context)
    }
  }

  private static func validatedTag(_ object: Object) throws -> UInt8 {
    let value = try object.value(as: IntegerValue.self).value
    guard let tag = UInt8(exactly: value) else {
      throw Error.rangeCheck
    }
    return tag
  }
}
