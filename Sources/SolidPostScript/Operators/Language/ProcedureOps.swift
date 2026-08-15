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
    public func execute(context: isolated Context) throws {

      _ = context.executionModes.pop()
      let deferred = try context.operands.popToMark().reversed()

      let array: Object =
        try context.packingMode == .packed
        ? .packedArray(deferred, kind: .executable)
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
    public func execute(context: isolated Context) throws {

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

      return .packedArray(elements, kind: .executable)
    }

  }

}
