//
//  ArrayOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let arrayOps: [OperatorValue] = [
    CreateArray.instance,
    ConstructArray.instance,
    ArrayStore.instance,
    ArrayLoad.instance,
  ]

  /// Implements the PostScript `array` operator.
  public enum CreateArray: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["array"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let count: IntegerValue = try context.operands.popAs()

      let countValue = Int(count.value)
      try context.limitCheck(size: countValue, objectType: .array)

      let array: [Object] = Array(repeating: .null, count: countValue)
      context.operands.push(try .array(array, access: .unlimited, vm: context.allocationMode, kind: .literal))
    }
  }

  /// Implements the PostScript `]` operator.
  public enum ConstructArray: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["]"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let ops = try context.operands.popToMark().reversed()
      context.operands.push(try .array(ops, access: .unlimited, vm: context.allocationMode, kind: .literal))
    }
  }

  /// Implements the PostScript `astore` operator.
  public enum ArrayStore: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["astore"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arrayObj = try context.operands.pop()
      let array = try arrayObj.value(as: ArrayValue.self)
      let items = try context.operands.pop(count: array.count.signed)

      try array.updateObjects(items.reversed(), startingAt: 0)

      context.operands.push(arrayObj)
    }
  }

  /// Implements the PostScript `aload` operator.
  public enum ArrayLoad: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["aload"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let arrayObj = try context.operands.pop()
      let array = try arrayObj.value(as: CollectionValue.self)

      context.operands.push(contentsOf: try array.objects(in: 0..<array.count).reversed())

      context.operands.push(arrayObj)
    }
  }

}
