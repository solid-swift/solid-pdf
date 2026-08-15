//
//  VMOps.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation

extension Operators {

  static let vmOps: [OperatorValue] = [
    Save.instance,
    Restore.instance,
    GetGlobal.instance,
    SetGlobal.instance,
    CheckGlobal.instance,
  ]

  /// Implements the PostScript `save` operator.
  public enum Save: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["save"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let snapshot = try context.snapshot()
      let save = SaveValue(snapshot: snapshot)

      context.operands.push(.init(value: save))
    }
  }

  /// Implements the PostScript `restore` operator.
  public enum Restore: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["restore"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let save: SaveValue = try context.operands.popAs()

      try save.snapshot.restore(to: context)
    }
  }

  /// Implements the PostScript `setglobal` operator.
  public enum SetGlobal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setglobal"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let mode: BooleanValue = try context.operands.popAs()

      context.allocationMode = mode.value ? .global : .local
    }
  }

  /// Implements the PostScript `currentglobal` operator.
  public enum GetGlobal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentglobal"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      context.operands.push(.boolean(context.allocationMode == .global))
    }
  }

  /// Implements the PostScript `gcheck` operator.
  public enum CheckGlobal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["gcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let obj = try context.operands.pop()

      let result =
        if let val = obj.value as? CompositeValue {
          val.vm == .global
        } else {
          true
        }

      context.operands.push(.boolean(result))
    }
  }

}
