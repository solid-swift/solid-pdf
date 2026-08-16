//
//  DictionaryOps.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation

extension Operators {

  static let dictionaryOps: [OperatorValue] = [
    CreateDictionary.instance,
    ConstructDictionary.instance,
    MaxLength.instance,
    Begin.instance,
    End.instance,
    Define.instance,
    Load.instance,
    Store.instance,
    Undefine.instance,
    Known.instance,
    Where.instance,
    CurrentDict.instance,
    CountDictStack.instance,
    CopyDictStack.instance,
    ClearDictStack.instance,
  ]

  /// Implements the PostScript `dict` operator.
  public enum CreateDictionary: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["dict"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let capacity: IntegerValue = try context.operands.popAs()

      let capacityValue = Int(capacity.value)
      try context.limitCheck(size: capacityValue, objectType: .dictionary)

      let dict = DictionaryValue.Storage(minimumCapacity: capacityValue)
      context.operands.push(try .dictionary(dict, access: .unlimited, vm: context.allocationMode, kind: .literal))
    }
  }

  /// Implements the PostScript `>>` operator.
  public enum ConstructDictionary: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = [">>"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let elements = try context.operands.popToMark().reversed()
      guard elements.count.isMultiple(of: 2) else {
        throw Error.rangeCheck
      }
      try context.limitCheck(size: elements.count / 2, objectType: .dictionary)
      let entries: [(key: Object, value: Object)] = elements.chunks(ofCount: 2)
        .map { pair in
          let first = pair[pair.startIndex]
          let last = pair[pair.index(after: pair.startIndex)]
          return (first, last)
        }
      return context.operands.push(
        try .dictionary(uniqueKeysWithValues: entries, access: .unlimited, vm: context.allocationMode, kind: .literal)
      )
    }
  }

  /// Implements the PostScript `maxlength` operator.
  public enum MaxLength: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["maxlength"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op: DictionaryValue = try context.operands.peekAs()
      try op.access.check(.read)
      context.operands.push(try NumericSemantics.integer(validating: op.capacity))
    }
  }

  /// Implements the PostScript `begin` operator.
  public enum Begin: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["begin"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      try context.dictionaries.push(op)
    }
  }

  /// Implements the PostScript `end` operator.
  public enum End: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["end"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      _ = try context.dictionaries.pop()
    }
  }

  /// Implements the PostScript `def` operator.
  public enum Define: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["def"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (value, key) = try context.operands.pop2()

      let dictionary = try context.dictionaries.currentDictionary()
      try context.updateDictionary(dictionary, value: value, forKey: key)
    }
  }

  /// Implements the PostScript `load` operator.
  public enum Load: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["load"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let key = try context.operands.pop()
      let value = try context.dictionaries.object(forKey: key)

      context.operands.push(value)
    }
  }

  /// Implements the PostScript `store` operator.
  public enum Store: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["store"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (value, key) = try context.operands.pop2()

      let dictionary = try context.dictionaries.object(forKeyIfExists: key)?.source
        .value(as: DictionaryValue.self) ?? context.dictionaries.currentDictionary()
      try context.updateDictionary(dictionary, value: value, forKey: key)
    }
  }

  /// Implements the PostScript `undef` operator.
  public enum Undefine: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["undef"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (key, op) = try context.operands.pop2()

      guard let dict = op.value as? DictionaryValue else {
        throw Error.typeCheck
      }

      _ = try dict.removeObject(forKey: key)
    }
  }

  /// Implements the PostScript `known` operator.
  public enum Known: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["known"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (key, op) = try context.operands.pop2()

      guard let dict = op.value as? DictionaryValue else {
        throw Error.typeCheck
      }

      let exists = try dict.object(forKeyIfExists: key) != nil

      context.operands.push(.boolean(exists))
    }
  }

  /// Implements the PostScript `where` operator.
  public enum Where: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["where"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let key = try context.operands.pop()

      if let (dict, _) = try context.dictionaries.object(forKeyIfExists: key) {
        context.operands.push(.boolean(true), dict)
      } else {
        context.operands.push(.boolean(false))
      }
    }
  }

  /// Implements the PostScript `currentdict` operator.
  public enum CurrentDict: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentdict"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(try context.dictionaries.current())
    }
  }

  /// Implements the PostScript `countdictstack` operator.
  public enum CountDictStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["countdictstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.operands.push(try NumericSemantics.integer(validating: context.dictionaries.depth))
    }
  }

  /// Implements the PostScript `dictstack` operator.
  public enum CopyDictStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["dictstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let arrayObj = try context.operands.pop()
      let array = try arrayObj.value(as: ArrayValue.self)
      guard array.count >= context.dictionaries.depth else {
        throw Error.rangeCheck
      }
      let dicts = try context.dictionaries.peek(count: context.dictionaries.depth)
      try array.updateObjects(dicts.reversed(), startingAt: 0)
      context.operands.push(try .array(sharing: array, subRange: 0..<dicts.count.unsigned, kind: arrayObj.kind))
    }
  }

  /// Implements the PostScript `cleardictstack` operator.
  public enum ClearDictStack: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["cleardictstack"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      context.dictionaries.clear()
    }
  }

}
