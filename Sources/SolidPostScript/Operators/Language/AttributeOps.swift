//
//  AttributeOps.swift
//
//
//  Created by Kevin Wooten on 6/30/24.
//

import Foundation

extension Operators {

  static let attributeOps: [OperatorValue] = [
    TypeOf.instance,
    ReduceAccessToReadOnly.instance,
    ReduceAccessToExecuteOnly.instance,
    ReduceAccessToNoAccess.instance,
    TestExecutableAttribute.instance,
    TestReadableAttribute.instance,
    TestWritableAttribute.instance,
    ChangeToLiteral.instance,
    ChangeToExecutable.instance,
  ]

  /// Implements the PostScript `type` operator.
  public enum TypeOf: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["type"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()
      let typeName = op.type.name

      context.operands.push(.executableName(typeName))
    }
  }

  private static func reduceAccess(
    to access: ObjectAccess,
    includingDictionaries: Bool,
    context: isolated Context
  ) throws {
    let object = try context.operands.pop()
    let reduced = switch object.value {
    case let value as ArrayValue:
      try reduceAccess(of: object, value: value, to: access)
    case let value as PackedArrayValue:
      try reduceAccess(of: object, value: value, to: access)
    case let value as FileValue:
      try reduceAccess(of: object, value: value, to: access)
    case let value as StringValue:
      try reduceAccess(of: object, value: value, to: access)
    case let value as DictionaryValue where includingDictionaries:
      try reduceAccess(of: object, value: value, to: access)
    default:
      throw Error.typeCheck
    }
    context.operands.push(reduced)
  }

  private static func reduceAccess<Value>(
    of object: Object,
    value: Value,
    to access: ObjectAccess
  ) throws -> Object where Value: UpdatableAccessValue {
    var value = value
    try value.reduceAccess(to: access)
    return .init(value: value, kind: object.kind)
  }

  /// Implements the PostScript `executeonly` operator.
  public enum ReduceAccessToExecuteOnly: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["executeonly"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try reduceAccess(to: .executeOnly, includingDictionaries: false, context: context)
    }
  }

  /// Implements the PostScript `readonly` operator.
  public enum ReduceAccessToReadOnly: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["readonly"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try reduceAccess(to: .readOnly, includingDictionaries: true, context: context)
    }
  }

  /// Implements the PostScript `noaccess` operator.
  public enum ReduceAccessToNoAccess: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["noaccess"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try reduceAccess(to: .noAccess, includingDictionaries: true, context: context)
    }
  }

  /// Implements the PostScript `xcheck` operator.
  public enum TestExecutableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["xcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      context.operands.push(.boolean(op.kind == .executable))
    }
  }

  private enum AccessTest {
    case read
    case write
  }

  private static func test(_ test: AccessTest, context: isolated Context) throws {
    let object = try context.operands.pop()
    let result = switch object.value {
    case let value as ArrayValue:
      test == .read ? value.access.isReadAllowed : value.access.isWriteAllowed
    case let value as PackedArrayValue:
      test == .read ? value.access.isReadAllowed : false
    case let value as DictionaryValue:
      test == .read ? value.access.isReadAllowed : value.access.isWriteAllowed
    case let value as FileValue:
      test == .read ? value.isReadable : value.isWritable
    case let value as StringValue:
      test == .read ? value.access.isReadAllowed : value.access.isWriteAllowed
    default:
      throw Error.typeCheck
    }
    context.operands.push(.boolean(result))
  }

  /// Implements the PostScript `rcheck` operator.
  public enum TestReadableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["rcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try test(.read, context: context)
    }
  }

  /// Implements the PostScript `wcheck` operator.
  public enum TestWritableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["wcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      try test(.write, context: context)
    }
  }

  /// Implements the PostScript `cvlit` operator.
  public enum ChangeToLiteral: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvlit"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      context.operands.push(.init(value: op.value, kind: .literal))
    }
  }

  /// Implements the PostScript `cvx` operator.
  public enum ChangeToExecutable: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvx"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      context.operands.push(.init(value: op.value, kind: .executable))
    }
  }

}
