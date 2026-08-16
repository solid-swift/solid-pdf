//
//  StackOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

extension Operators {

  static let stackOps: [OperatorValue] = [
    Pop.instance,
    Exchange.instance,
    Duplicate.instance,
    Index.instance,
    Roll.instance,
    Clear.instance,
    Count.instance,
    Mark.instance,
    CountToMark.instance,
    ClearToMark.instance,
  ]

  /// Implements the PostScript `pop` operator.
  public enum Pop: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["pop"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      _ = try context.operands.pop()
    }
  }

  /// Implements the PostScript `exch` operator.
  public enum Exchange: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["exch"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let (arg2, arg1) = try context.operands.pop2()
      context.operands.push(arg1, arg2)
    }
  }

  /// Implements the PostScript `dup` operator.
  public enum Duplicate: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["dup"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let arg1 = try context.operands.pop()
      context.operands.push(arg1, arg1)
    }
  }

  /// Implements the PostScript `index` operator.
  public enum Index: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["index"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let index: IntegerValue = try context.operands.popAs()
      let op = try context.operands.peek(at: Int(index.value))
      context.operands.push(op)
    }
  }

  /// Implements the PostScript `roll` operator.
  public enum Roll: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["roll"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let (times, count): (IntegerValue, IntegerValue) = try context.operands.popAs()
      guard count.value >= 0 else {
        throw Error.rangeCheck
      }
      guard count.value != 0 else {
        return
      }
      var ops = try context.operands.pop(count: Int(count.value))
      let shift = times.value % count.value
      let start = Int(shift >= 0 ? shift : shift + count.value)
      ops.rotate(toStartAt: start)
      context.operands.push(contentsOf: ops)
    }
  }

  /// Implements the PostScript `clear` operator.
  public enum Clear: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["clear"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      _ = try context.operands.pop(count: context.operands.depth)
    }
  }

  /// Implements the PostScript `count` operator.
  public enum Count: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["count"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(try NumericSemantics.integer(validating: context.operands.depth))
    }
  }

  /// Implements the PostScript `mark` operator.
  public enum Mark: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["mark", "[", "<<"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async {
      context.operands.push(.mark)
    }
  }

  /// Implements the PostScript `counttomark` operator.
  public enum CountToMark: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["counttomark"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(try NumericSemantics.integer(validating: context.operands.countToMark()))
    }
  }

  /// Implements the PostScript `cleartomark` operator.
  public enum ClearToMark: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cleartomark"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      _ = try context.operands.pop(count: context.operands.countToMark())
    }
  }

}
