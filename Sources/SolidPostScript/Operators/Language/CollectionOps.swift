//
//  CollectionOps.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation

extension Operators {

  static let collectionOps: [OperatorValue] = [
    Length.instance,
    Get.instance,
    Put.instance,
    GetInterval.instance,
    PutInterval.instance,
    ForAll.instance,
  ]

  /// Implements the PostScript `length` operator.
  public enum Length: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["length"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      let length: UInt
      switch op.value {
      case let coll as CollectionValue:
        try coll.access.check(.read)
        length = coll.count
      case let dictionary as DictionaryValue:
        try dictionary.access.check(.read)
        length = dictionary.count
      case let string as StringValue:
        try string.access.check(.read)
        length = string.count
      case let name as NameValue:
        length = try name.value.count.unsigned
      default:
        throw Error.typeCheck
      }

      context.operands.push(try NumericSemantics.integer(validating: length))
    }
  }

  /// Implements the PostScript `get` operator.
  public enum Get: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["get"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (indexOrKey, source) = try context.operands.pop2()

      let value: Object =
        switch (source.value, indexOrKey.value) {
        case (let coll as CollectionValue, let index as IntegerValue):
          try coll.object(at: index.value.unsigned)
        case (let dictionary as DictionaryValue, _):
          try dictionary.object(forKey: indexOrKey)
        case (let string as StringValue, let index as IntegerValue):
          .integer(Int32(try string.character(at: index.value.unsigned)))
        default:
          throw Error.typeCheck
        }
      context.operands.push(value)
    }
  }

  /// Implements the PostScript `put` operator.
  public enum Put: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["put"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (value, indexOrKey, target) = try context.operands.pop3()

      switch (target.value, indexOrKey.value, value.value) {
      case (let coll as ArrayValue, let index as IntegerValue, _):
        try coll.updateObject(value, at: index.value.unsigned)
      case (let dictionary as DictionaryValue, _, _):
        try context.updateDictionary(dictionary, value: value, forKey: indexOrKey)
      case (let string as StringValue, let index as IntegerValue, let char as IntegerValue):
        guard let byte = UInt8(exactly: char.value) else {
          throw Error.rangeCheck
        }
        try string.updateCharacter(byte, at: index.value.unsigned)
      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `getinterval` operator.
  public enum GetInterval: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["getinterval"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (count, index, source) = try context.operands.pop3()

      switch (source.value, index.value, count.value) {
      case (let array as ArrayValue, let index as IntegerValue, let count as IntegerValue):
        try array.access.check(.read)
        let startIndex = try index.value.unsigned
        let endIndex = try startIndex + count.value.unsigned
        context.operands.push(try .array(sharing: array, subRange: startIndex..<endIndex, kind: source.kind))

      case (let array as PackedArrayValue, let index as IntegerValue, let count as IntegerValue):
        let startIndex = try index.value.unsigned
        let endIndex = try startIndex + count.value.unsigned
        let elements = try array.objects(in: startIndex..<endIndex)
        context.operands.push(try .packedArray(elements, vm: array.vm, kind: source.kind))

      case (let string as StringValue, let index as IntegerValue, let count as IntegerValue):
        try string.access.check(.read)
        let startIndex = try index.value.unsigned
        let endIndex = try startIndex + count.value.unsigned
        context.operands.push(try .string(sharing: string, subRange: startIndex..<endIndex, kind: source.kind))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `putinterval` operator.
  public enum PutInterval: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["putinterval"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (source, index, target) = try context.operands.pop3()

      switch (source.value, index.value, target.value) {
      case (let arr1 as CollectionValue, let index as IntegerValue, let arr2 as ArrayValue):
        let objects = try Array(arr1.objects(in: arr1.range))
        try arr2.updateObjects(objects, startingAt: index.value.unsigned)

      case (let str1 as StringValue, let index as IntegerValue, let str2 as StringValue):
        try str2.updateCharacters(str1.characters(in: str1.range), startingAt: index.value.unsigned)

      default:
        throw Error.typeCheck
      }
    }
  }

  /// Implements the PostScript `forall` operator.
  public enum ForAll: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["forall"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (proc, source) = try context.operands.pop2()
      try proc.checkProcedure()

      switch source.value {
      case let coll as CollectionValue:
        try coll.access.check(.read)
        for idx in 0..<coll.count {
          let result = try await context.execute(proc: proc, ops: [try coll.object(at: idx)])
          if !result {
            break
          }
        }

      case let dict as DictionaryValue:
        try dict.access.check(.read)
        for key in dict.keys {
          let value = try dict.object(forKey: key)
          let result = try await context.execute(proc: proc, ops: [value, key])
          if !result {
            break
          }
        }

      case let string as StringValue:
        try string.access.check(.read)
        for idx in 0..<string.count {
          let result = try await context.execute(proc: proc, ops: [.integer(Int32(string.character(at: idx)))])
          if !result {
            break
          }
        }

      default:
        throw Error.typeCheck
      }
    }
  }

}
