//
//  StringOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

extension Operators {

  static let stringOps: [OperatorValue] = [
    CreateString.instance,
    AnchorSearch.instance,
    Search.instance,
  ]

  /// Implements the PostScript `string` operator.
  public enum CreateString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["string"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let count: IntegerValue = try context.operands.popAs()
      let countValue = Int(count.value)
      try context.limitCheck(size: countValue, objectType: .string)
      let data = Data(repeating: 0, count: countValue)
      context.operands.push(.string(data, access: .unlimited, vm: context.allocationMode, kind: .literal))
    }
  }

  /// Implements the PostScript `anchorsearch` operator.
  public enum AnchorSearch: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["anchorsearch"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (seekObj, stringObj) = try context.operands.pop2()
      let string = try stringObj.value(as: StringValue.self)
      let seek = try seekObj.value(as: StringValue.self)
      try string.access.check(.read)
      try seek.access.check(.read)

      if string.count >= seek.count, try string.characters(in: 0..<seek.count) == seek.characters(in: seek.range) {

        let postObj: Object = try .string(sharing: string, subRange: seek.count..., kind: stringObj.kind)

        context.operands.push(contentsOf: [.boolean(true), seekObj, postObj])
      } else {
        context.operands.push(contentsOf: [.boolean(false), stringObj])
      }
    }
  }

  /// Implements the PostScript `search` operator.
  public enum Search: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["search"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let (seekObj, stringObj) = try context.operands.pop2()
      let string = try stringObj.value(as: StringValue.self)
      let seek = try seekObj.value(as: StringValue.self)
      try string.access.check(.read)
      try seek.access.check(.read)

      if let matchRange = try string.firstRange(of: seek) {

        let match: Object = try .string(sharing: string, subRange: matchRange, kind: stringObj.kind)
        let pre: Object = try .string(sharing: string, subRange: ..<matchRange.lowerBound, kind: stringObj.kind)
        let post: Object = try .string(sharing: string, subRange: matchRange.upperBound..., kind: stringObj.kind)

        context.operands.push(contentsOf: [.boolean(true), pre, match, post])
      } else {
        context.operands.push(contentsOf: [.boolean(false), stringObj])
      }
    }
  }

}
