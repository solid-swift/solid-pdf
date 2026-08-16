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
    try userObjects(in: context.dictionaries.userDictionary())
  }

  private static func userObjects(in userDictionary: DictionaryValue) throws -> ArrayValue? {
    try userDictionary.object(forKeyIfExists: "UserObjects")?.value(as: ArrayValue.self)
  }

  private static func define(
    _ object: Object,
    at index: Int,
    in context: isolated Context
  ) throws {
    let userDictionary = try context.dictionaries.userDictionary()
    let current = try userObjects(in: userDictionary)
    let position = try index.unsigned
    if let current, position < current.count {
      try current.updateObject(object, at: position)
      return
    }

    let (doubledIndex, overflow) = index.multipliedReportingOverflow(by: 2)
    let count = max(50, overflow ? Int.max : doubledIndex)
    try context.limitCheck(
      size: count,
      objectType: .array,
      vm: .local,
      additionalDictionaryEntries: current == nil ? 1 : 0
    )

    var elements = Array(repeating: Object.null, count: count)
    if let current {
      let currentElements = try current.objects(in: current.range)
      elements.replaceSubrange(0..<currentElements.count, with: currentElements)
    }
    elements[index] = object

    let new = try ArrayValue(elements: elements, access: .unlimited, vm: .local)
    try context.updateDictionary(
      userDictionary,
      value: .init(value: new, kind: .literal),
      forKey: "UserObjects",
      additionalAllocationBytes: context.estimatedAllocationSize(count: count, objectType: .array)
    )
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
      guard index >= 0 else { throw Error.rangeCheck }

      try define(obj, at: index, in: context)
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

      try await obj.execute(context: context, method: .indirect)
    }
  }
}
