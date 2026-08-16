import Foundation

extension Operators {
  static let parameterOps: [OperatorValue] = [
    CurrentUserParams.instance,
    SetUserParams.instance,
    CurrentSystemParams.instance,
    SetSystemParams.instance,
    CurrentDevParams.instance,
    SetDevParams.instance,
  ]

  /// Implements the PostScript `currentuserparams` operator.
  public enum CurrentUserParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentuserparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      context.operands.push(try context.parameterDictionary(context.userParameters.values))
    }
  }

  /// Implements the PostScript `setuserparams` operator.
  public enum SetUserParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setuserparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let dictionary: DictionaryValue = try context.operands.popAs()
      try context.userParameters.update(from: dictionary)
      context.applyUserParameterLimits()
    }
  }

  /// Implements the PostScript `currentsystemparams` operator.
  public enum CurrentSystemParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentsystemparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      context.operands.push(try context.parameterDictionary(context.environment.systemParameters()))
    }
  }

  /// Implements the PostScript `setsystemparams` operator.
  public enum SetSystemParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setsystemparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let dictionary: DictionaryValue = try context.operands.popAs()
      try context.environment.updateSystemParameters(from: dictionary)
    }
  }

  /// Implements the PostScript `currentdevparams` operator.
  public enum CurrentDevParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentdevparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let identifier: StringValue = try context.operands.popAs()
      let device = try context.fileDevices.device(named: deviceName(identifier))
      let values = try (device as? any ParameterizedFileDevice)?.currentParameters() ?? [:]
      try context.limitCheck(size: values.count, objectType: .dictionary)
      context.operands.push(
        try .dictionary(values, access: .unlimited, vm: context.allocationMode, kind: .literal)
      )
    }
  }

  /// Implements the PostScript `setdevparams` operator.
  public enum SetDevParams: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setdevparams"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let (dictionaryObject, identifierObject) = try context.operands.pop2()
      let dictionary = try dictionaryObject.value(as: DictionaryValue.self)
      let identifier = try identifierObject.value(as: StringValue.self)
      let device = try context.fileDevices.device(named: deviceName(identifier))

      var entries: [Object: Object] = [:]
      try dictionary.forEachUnchecked { entries[$0] = $1 }
      entries = try context.environment.validateDevicePassword(in: entries)

      guard let parameterized = device as? any ParameterizedFileDevice else {
        guard entries.isEmpty else { throw Error.undefined }
        return
      }
      try parameterized.setParameters(entries)
    }
  }

  private static func deviceName(_ identifier: StringValue) throws -> String {
    var name = try identifier.characters(in: identifier.range)
    guard name.first == 37 else { throw Error.undefined }
    name.removeFirst()
    if name.last == 37 {
      name.removeLast()
    }
    guard !name.isEmpty, let value = String(data: name, encoding: .isoLatin1) else {
      throw Error.undefined
    }
    return value
  }
}

extension Context {
  func parameterDictionary(_ values: [String: ParameterValue]) throws -> Object {
    try limitCheck(size: values.count, objectType: .dictionary)
    return try .dictionary(
      uniqueKeysWithValues: values.map { (.literalName($0.key), $0.value.object(vm: allocationMode)) },
      access: .unlimited,
      vm: allocationMode,
      kind: .literal
    )
  }
}
