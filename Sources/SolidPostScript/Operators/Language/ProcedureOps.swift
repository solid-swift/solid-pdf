//
//  ProcedureOps.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

extension Operators {

  static let procedureOps: [OperatorValue] = [
    ConstructProcedure.instance,
    Bind.instance,
  ]

  /// Implements the PostScript `}` operator.
  public enum ConstructProcedure: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["}"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      _ = context.executionModes.pop()
      let deferred = try context.operands.popToMark().reversed()
      try context.limitCheck(size: deferred.count, objectType: .array)

      let array: Object =
        try context.packingMode == .packed
        ? .packedArray(deferred, vm: context.allocationMode, kind: .executable)
        : .array(deferred, access: .unlimited, vm: context.allocationMode, kind: .executable)

      context.operands.push(array)
    }
  }

  /// Implements the PostScript `bind` operator.
  public enum Bind: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["bind"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let proc = try context.operands.pop().value(as: (any CollectionValue).self)

      let bound = try bind(context: context, array: proc)

      context.operands.push(bound)
    }


    /// Performs the ``bind`` operation.
    public func bind(context: isolated Context, array: CollectionValue) throws -> Object {
      var elements = try array.objects(in: array.range)

      for index in elements.indices {

        let element = elements[index]
        if let name = element.value as? NameValue, element.kind == .executable {

          let value = try name.lookup(in: context)
          guard value.value is OperatorValue else {
            continue
          }
          elements[index] = value

        } else if element.kind == .executable, let proc = element.value as? CollectionValue {

          elements[index] = try bind(context: context, array: proc)
        }
      }

      try context.limitCheck(size: elements.count, objectType: .array)
      let bound = try Object.packedArray(elements, vm: array.vm, kind: .executable)
      return try recognizeIdiom(context: context, candidate: bound)
    }

    private func recognizeIdiom(context: isolated Context, candidate: Object) throws -> Object {
      guard context.userParameters.boolean("IdiomRecognition") else { return candidate }

      var sets: [DictionaryValue] = []
      for (_, entry) in try ResourceRuntime.storedEntries(in: "IdiomSet", context: context) {
        if let dictionary = entry.instance.value as? DictionaryValue {
          sets.append(dictionary)
        }
      }

      let candidateVM = (candidate.value as? any CompositeValue)?.vm
      for set in sets {
        var replacement: Object?
        try set.forEachUnchecked { _, pairObject in
          guard replacement == nil,
                let pair = pairObject.value as? any CollectionValue,
                pair.count == 2
          else { return }
          let procedures = try pair.objects(in: pair.range)
          guard try proceduresMatch(candidate, procedures[0], depth: 0) else { return }
          let substitute = procedures[1]
          if candidateVM == .global,
             let composite = substitute.value as? any CompositeValue,
             composite.vm == .local
          {
            return
          }
          replacement = substitute
        }
        if let replacement { return replacement }
      }
      return candidate
    }

    private func proceduresMatch(_ lhs: Object, _ rhs: Object, depth: Int) throws -> Bool {
      if lhs == rhs { return true }
      guard let lhsArray = lhs.value as? any CollectionValue,
            let rhsArray = rhs.value as? any CollectionValue
      else {
        return false
      }
      guard depth < 10, lhsArray.count == rhsArray.count else { return false }
      let lhsElements = try lhsArray.objects(in: lhsArray.range)
      let rhsElements = try rhsArray.objects(in: rhsArray.range)
      for (lhsElement, rhsElement) in zip(lhsElements, rhsElements) {
        guard try proceduresMatch(lhsElement, rhsElement, depth: depth + 1) else { return false }
      }
      return true
    }

  }

}
