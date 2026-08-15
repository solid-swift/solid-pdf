//
//  PackedArrayOps.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Operators {

  static let packedArrayOps: [OperatorValue] = [
    ConstructPackedArray.instance,
    SetPacking.instance,
    GetPacking.instance,
  ]

  /// Implements the PostScript `packedarray` operator.
  public enum ConstructPackedArray: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["packedarray"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let count: IntegerValue = try context.operands.popAs()
      let ops = try context.operands.pop(count: count.value).reversed()
      context.operands.push(.packedArray(ops, kind: .literal))
    }
  }

  /// Implements the PostScript `setpacking` operator.
  public enum SetPacking: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setpacking"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      let mode: BooleanValue = try context.operands.popAs()
      context.packingMode = mode.value ? .packed : .unpacked
    }
  }

  /// Implements the PostScript `currentpacking` operator.
  public enum GetPacking: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentpacking"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      context.operands.push(.boolean(context.packingMode == .packed))
    }
  }

}
