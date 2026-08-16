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
    public func execute(context: isolated Context) throws {

      let op = try context.operands.pop()
      let typeName = op.type.name

      context.operands.push(.executableName(typeName))
    }
  }

  private static func reduceAccess(to access: ObjectAccess, context: isolated Context) throws {

    let op = try context.operands.pop()

    guard var value = op.value as? AccessedValue else {
      throw Error.typeCheck
    }

    try value.reduceAccess(to: access)
    context.operands.push(.init(value: value, kind: op.kind))
  }

  /// Implements the PostScript `executeonly` operator.
  public enum ReduceAccessToExecuteOnly: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["executeonly"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      try reduceAccess(to: .executeOnly, context: context)
    }
  }

  /// Implements the PostScript `readonly` operator.
  public enum ReduceAccessToReadOnly: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["readonly"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      try reduceAccess(to: .readOnly, context: context)
    }
  }

  /// Implements the PostScript `noaccess` operator.
  public enum ReduceAccessToNoAccess: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["noaccess"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      try reduceAccess(to: .noAccess, context: context)
    }
  }

  /// Implements the PostScript `xcheck` operator.
  public enum TestExecutableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["xcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let op = try context.operands.pop()

      context.operands.push(.boolean(op.kind == .executable))
    }
  }

  private static func test(_ keyPath: KeyPath<ObjectAccess, Bool>, context: isolated Context) throws {

    let op = try context.operands.pop()

    if let file = op.value as? FileValue {
      let result =
        if keyPath == \ObjectAccess.isReadAllowed {
          file.isReadable
        } else if keyPath == \ObjectAccess.isWriteAllowed {
          file.isWritable
        } else {
          file.access[keyPath: keyPath]
        }
      context.operands.push(.boolean(result))
      return
    }

    guard let value = op.value as? AccessedValue else {
      throw Error.typeCheck
    }

    context.operands.push(.boolean(value.access[keyPath: keyPath]))
  }

  /// Implements the PostScript `rcheck` operator.
  public enum TestReadableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["rcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      try test(\.isReadAllowed, context: context)
    }
  }

  /// Implements the PostScript `wcheck` operator.
  public enum TestWritableAttribute: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["wcheck"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {
      try test(\.isWriteAllowed, context: context)
    }
  }

  /// Implements the PostScript `cvlit` operator.
  public enum ChangeToLiteral: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cvlit"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

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
    public func execute(context: isolated Context) throws {

      let op = try context.operands.pop()

      context.operands.push(.init(value: op.value, kind: .executable))
    }
  }

}
