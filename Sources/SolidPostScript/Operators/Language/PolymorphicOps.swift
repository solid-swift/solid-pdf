//
//  PolymorphicOps.swift
//
//
//  Created by Kevin Wooten on 6/28/24.
//

import Foundation

extension Operators {

  static let polymorphicOps: [OperatorValue] = [
    Copy.instance,
    Token.instance,
  ]

  /// Implements the PostScript `copy` operator.
  public enum Copy: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["copy"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let opObj = try context.operands.pop()
      switch opObj.type {

      // Copy stack
      case .integer:
        let count = try opObj.value(as: IntegerValue.self)
        guard count.value >= 0 else {
          throw Error.rangeCheck
        }
        let ops = try context.operands.peek(count: Int(count.value))
        context.operands.push(contentsOf: ops)

      // Copy array
      case .array:
        let array1 = try context.operands.pop().value(as: CollectionValue.self)
        let array2 = try opObj.value(as: ArrayValue.self)
        try array2.updateObjects(array1.objects(in: array1.range), startingAt: 0)
        context.operands.push(try .array(sharing: array2, subRange: array1.range, kind: opObj.kind))

      // Copy dictionary
      case .dictionary:
        let dict1 = try context.operands.pop().value(as: DictionaryValue.self)
        let dict2 = try opObj.value(as: DictionaryValue.self)
        try context.updateDictionary(dict2, from: dict1)
        context.operands.push(opObj)

      // Copy string
      case .string:
        let str1 = try context.operands.pop().value(as: StringValue.self)
        let str2 = try opObj.value(as: StringValue.self)
        try str2.updateCharacters(str1.characters(in: str1.range), startingAt: 0)
        context.operands.push(try .string(sharing: str2, subRange: str1.range, kind: opObj.kind))

      default:
        throw Error.typeCheck
      }
    }
  }

  /// A lexical token recognized in PostScript source.
  public enum Token: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["token"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let op = try context.operands.pop()

      switch op.type {
      case .string:
        let string = try op.value(as: StringValue.self)
        let scanner = try Scanner(content: string.characters(in: string.range))
        let reader = TokenObjectIterator(scanner: scanner)

        if let object = try reader.nextScanned(context: context)?.object {

          let post: Object = try .string(
            sharing: string,
            subRange: (string.count - UInt(scanner.available.unsigned))...,
            kind: op.kind
          )

          context.operands.push(contentsOf: [.boolean(true), object, post])
        } else {
          context.operands.push(.boolean(false))
        }

      case .file:
        let file = try op.value(as: FileValue.self)
        try file.checkReadable()
        let scanner = try Scanner(file: file.file)
        let reader = TokenObjectIterator(scanner: scanner)

        if let object = try await reader.nextContextual(context: context)?.object {

          context.operands.push(contentsOf: [.boolean(true), object])
        } else {
          context.operands.push(.boolean(false))
        }

      default:
        throw Error.typeCheck
      }
    }
  }

}
