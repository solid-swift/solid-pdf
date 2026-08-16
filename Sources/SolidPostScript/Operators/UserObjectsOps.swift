//
//  UserObjectsOps.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation

extension Operators {

  static let userObjectsOps: [OperatorValue] = [
    DefineUserObject.instance,
    UndefineUserObject.instance,
    ExecUserObject.instance,
  ]

  private static func userObjects(in context: isolated Context) throws -> ArrayValue? {

    return try context.dictionaries.userDictionary()
      .object(forKeyIfExists: "UserObjects")?
      .value(as: ArrayValue.self)
  }

  private static func userObjects(in context: isolated Context, for index: Int) throws -> ArrayValue {

    let current = try userObjects(in: context)
    guard let current, index < current.count else {

      let count = max(50, index * 2)
      let new = try ArrayValue(elements: .init(repeating: nil, count: count), access: .unlimited, vm: .local)
      if let current {
        try new.updateObjects(current.objects(in: current.range), startingAt: 0)
      }

      _ = try context.dictionaries.updateObject(.init(value: new, kind: .literal), forKey: "UserObjects")

      return new
    }

    return current
  }

  /// Implements the PostScript `defineuserobject` operator.
  public enum DefineUserObject: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["defineuserobject"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (obj, indexObj) = try context.operands.pop2()
      let index = Int(try indexObj.value(as: IntegerValue.self).value)

      let userObjects = try userObjects(in: context, for: index)
      try userObjects.updateObject(obj, at: index.unsigned)
    }
  }

  /// Implements the PostScript `undefineuserobject` operator.
  public enum UndefineUserObject: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["undefineuserobject"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let indexValue = try context.operands.popAs(IntegerValue.self).value
      let index = Int(indexValue)

      guard let userObjects = try userObjects(in: context) else {
        return
      }

      guard index < userObjects.count else {
        throw Error.rangeCheck
      }

      try userObjects.updateObject(.null, at: index.unsigned)
    }
  }

  /// Implements the PostScript `execuserobject` operator.
  public enum ExecUserObject: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["execuserobject"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let indexValue = try context.operands.popAs(IntegerValue.self).value
      let index = Int(indexValue)

      guard let userObjects = try userObjects(in: context) else {
        throw Error.undefined
      }

      guard index < userObjects.count else {
        throw Error.rangeCheck
      }

      let obj = try userObjects.object(at: index.unsigned)

      context.operands.push(obj)
    }
  }
}
