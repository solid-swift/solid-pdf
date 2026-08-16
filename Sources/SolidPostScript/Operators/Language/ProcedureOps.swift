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
      let procedure = try context.operands.pop()
      try procedure.checkProcedure()
      var state = BindingState()
      let bound = try bind(context: context, procedure: procedure, state: &state)
      context.operands.push(bound)
    }

    /// Performs the ``bind`` operation.
    public func bind(context: isolated Context, array: CollectionValue) throws -> Object {
      var state = BindingState()
      return try bind(
        context: context,
        procedure: Object(value: array, kind: .executable),
        state: &state
      )
    }

    private struct BindingIdentity: Hashable {
      let storage: ObjectIdentifier
      let range: Range<Int>?
    }

    private struct BindingState {
      var active: Set<BindingIdentity> = []
      var results: [BindingIdentity: Object] = [:]
    }

    private func bind(
      context: isolated Context,
      procedure: Object,
      state: inout BindingState
    ) throws -> Object {
      let collection = try procedure.value(as: (any CollectionValue).self)
      let identity = bindingIdentity(of: collection)
      if let identity, let result = state.results[identity] { return result }
      if let identity, !state.active.insert(identity).inserted { return procedure }
      defer {
        if let identity { state.active.remove(identity) }
      }

      switch collection {
      case let array as ArrayValue where array.access == .unlimited:
        let elements = try boundElements(context: context, collection: array, state: &state)
        try array.updateObjects(elements, startingAt: 0)

      case is ArrayValue:
        if let identity { state.results[identity] = procedure }
        return procedure

      case let packed as PackedArrayValue:
        let elements = try boundElements(context: context, collection: packed, state: &state)
        try packed.replaceElementsForBinding(elements)

      default:
        break
      }

      let result = try IdiomRecognizer.recognize(candidate: procedure, context: context)
      if let identity { state.results[identity] = result }
      return result
    }

    private func bindingIdentity(of collection: any CollectionValue) -> BindingIdentity? {
      guard let identifiable = collection as? SnapshotIdentifiableValue else { return nil }
      let range = (collection as? ArrayValue)?.refRange
      return BindingIdentity(storage: identifiable.snapshotIdentity, range: range)
    }

    private func boundElements(
      context: isolated Context,
      collection: any CollectionValue,
      state: inout BindingState
    ) throws -> [Object] {
      var elements: [Object] = []
      elements.reserveCapacity(Int(collection.count))
      collection.forEachUnchecked { elements.append($0) }

      for index in elements.indices {
        let element = elements[index]
        if element.kind == .executable, let name = element.value as? NameValue {
          do {
            let value = try name.lookup(in: context)
            if value.value is OperatorValue { elements[index] = value }
          } catch Error.undefined {
            continue
          }
        } else if element.isProcedure {
          let nested = try bind(context: context, procedure: element, state: &state)
          elements[index] = try readOnly(nested)
        }
      }
      return elements
    }

    private func readOnly(_ procedure: Object) throws -> Object {
      switch procedure.value {
      case var array as ArrayValue where array.access == .unlimited:
        try array.setAccess(to: .readOnly)
        return Object(value: array, kind: procedure.kind)
      case var packed as PackedArrayValue where packed.access == .unlimited:
        try packed.setAccess(to: .readOnly)
        return Object(value: packed, kind: procedure.kind)
      default:
        return procedure
      }
    }
  }

}
