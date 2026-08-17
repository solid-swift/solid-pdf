//
//  VMStoredObject.swift
//

import Foundation
import SolidCore

/// An object retained by managed PostScript VM storage.
///
/// Composite cases retain a logical edge lease and a weak materializer instead of retaining the
/// target backing through Swift ARC. Simple values remain inline.
struct VMStoredObject: Hashable, @unchecked Sendable {

  final class Reference: @unchecked Sendable {
    let edge: VMEdgeLease
    let hashValue: Int
    let objectType: ObjectType
    private let materializeBody: @Sendable () -> Object?

    init(
      allocation: VMAllocation,
      owner: AnyObject,
      hashValue: Int,
      objectType: ObjectType,
      materialize: @escaping @Sendable () -> Object?
    ) {
      self.edge = VMEdgeLease(allocation: allocation, owner: owner)
      self.hashValue = hashValue
      self.objectType = objectType
      self.materializeBody = materialize
    }

    var object: Object {
      materializeBody().neverNil(
        "PostScript VM retained an unavailable \(objectType) backing (\(edge.allocation.debugState))"
      )
    }

    func copiedForSnapshot() -> Reference {
      guard let owner = edge.owner else {
        preconditionFailure("Cannot snapshot a reclaimed PostScript VM object")
      }
      return Reference(
        allocation: edge.allocation,
        owner: owner,
        hashValue: hashValue,
        objectType: objectType,
        materialize: materializeBody
      )
    }
  }

  private enum Storage: @unchecked Sendable {
    case inline(Object)
    case reference(Reference)
  }

  private let storage: Storage

  init(_ object: Object) {
    if let composite = object.value as? VMStoredCompositeValue {
      self = composite.storedObject(kind: object.kind)
    } else {
      self.storage = .inline(object)
    }
  }

  private init(reference: Reference) {
    self.storage = .reference(reference)
  }

  static func reference(
    allocation: VMAllocation,
    owner: AnyObject,
    object: Object,
    materialize: @escaping @Sendable () -> Object?
  ) -> Self {
    var hasher = Hasher()
    object.hash(into: &hasher)
    return Self(reference: Reference(
      allocation: allocation,
      owner: owner,
      hashValue: hasher.finalize(),
      objectType: object.type,
      materialize: materialize
    ))
  }

  var object: Object {
    switch storage {
    case .inline(let object): object
    case .reference(let reference): reference.object
    }
  }

  var allocation: VMAllocation? {
    switch storage {
    case .inline: nil
    case .reference(let reference): reference.edge.allocation
    }
  }

  func refreshEdge() {
    if case .reference(let reference) = storage {
      reference.edge.refresh()
    }
  }

  func identifyEdgeSource(_ allocation: VMAllocation) {
    if case .reference(let reference) = storage {
      reference.edge.identifySource(allocation)
    }
  }

  func copiedForSnapshot() -> Self {
    switch storage {
    case .inline:
      self
    case .reference(let reference):
      Self(reference: reference.copiedForSnapshot())
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.object == rhs.object
  }

  func hash(into hasher: inout Hasher) {
    switch storage {
    case .inline(let object): object.hash(into: &hasher)
    case .reference(let reference): hasher.combine(reference.hashValue)
    }
  }
}

protocol VMStoredCompositeValue: VMAllocatedCompositeValue {
  func storedObject(kind: ObjectKind) -> VMStoredObject
}

extension Collection where Element == VMStoredObject {
  var vmAllocations: [VMAllocation] { compactMap(\.allocation) }

  func refreshVMEdges() {
    forEach { $0.refreshEdge() }
  }

  func identifyVMEdgeSources(_ allocation: VMAllocation) {
    forEach { $0.identifyEdgeSource(allocation) }
  }
}
