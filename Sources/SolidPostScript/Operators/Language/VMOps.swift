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
    VMStatus.instance,
    VMReclaim.instance,
    SetVMThreshold.instance,
  ]

  /// Implements the PostScript `save` operator.
  public enum Save: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["save"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let snapshot = try context.snapshot()
      let save = SaveValue(snapshot: snapshot)
      context.saveDepth += 1
      context.registerLanguageSave(snapshot)

      context.operands.push(.init(value: save))
    }
  }

  /// Implements the PostScript `restore` operator.
  public enum Restore: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["restore"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let save: SaveValue = try context.operands.popAs()

      try save.snapshot.restore(to: context)
      context.didRestore(save.snapshot)
    }
  }

  /// Implements the PostScript `setglobal` operator.
  public enum SetGlobal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setglobal"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

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
    public func execute(context: isolated Context) async throws {

      context.operands.push(.boolean(context.allocationMode == .global))
    }
  }

  /// Implements the PostScript `gcheck` operator.
  public enum CheckGlobal: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["gcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

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

  /// Implements the PostScript `vmstatus` operator.
  public enum VMStatus: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["vmstatus"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let used = min(try context.estimatedVMUsage(in: context.allocationMode), Int(Int32.max))
      let maximum = context.allocationMode == .local
        ? context.userParameters.integer("MaxLocalVM")
        : Int32.max
      context.operands.push(
        .integer(maximum),
        .integer(Int32(used)),
        .integer(Int32(clamping: context.saveDepth))
      )
    }
  }

  /// Implements the PostScript `vmreclaim` operator.
  public enum VMReclaim: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["vmreclaim"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let value: IntegerValue = try context.operands.popAs()
      switch value.value {
      case -2 ... 0:
        context.userParameters.setInteger(value.value, for: "VMReclaim")
      case 1:
        ResourceRuntime.reclaimAutomaticResources(context: context, includeGlobal: false)
        _ = try context.estimatedVMUsage(in: .local)
      case 2:
        ResourceRuntime.reclaimAutomaticResources(context: context, includeGlobal: true)
        _ = try context.estimatedVMUsage(in: .local)
        _ = try context.estimatedVMUsage(in: .global)
      default:
        throw Error.rangeCheck
      }
    }
  }

  /// Implements the PostScript `setvmthreshold` operator.
  public enum SetVMThreshold: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setvmthreshold"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let value: IntegerValue = try context.operands.popAs()
      guard value.value >= -1 else { throw Error.rangeCheck }
      context.userParameters.setInteger(
        value.value == -1 ? UserParameterState.vmThresholdDefault : value.value,
        for: "VMThreshold"
      )
    }
  }

}
