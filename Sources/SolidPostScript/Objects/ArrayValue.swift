//
//  ArrayValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

extension Object {

  /// Performs the ``array`` operation.
  public static func array(_ elements: some Sequence<Object>, access: ObjectAccess, vm: VM, kind: ObjectKind) throws
    -> Self
  {
    .init(value: try ArrayValue(elements: Array(elements), access: access, vm: vm), kind: kind)
  }

  /// Performs the ``array`` operation.
  public static func array<R: ArrayValue.SubRangeExpression>(sharing: ArrayValue, subRange: R, kind: ObjectKind) throws
    -> Self
  {
    .init(value: try ArrayValue(sharing: sharing, subRange: subRange.relative(to: 0..<sharing.count)), kind: kind)
  }
}

extension ArrayValue: SnapshotIdentifiableValue {

  var snapshotIdentity: ObjectIdentifier { ObjectIdentifier(ref) }

}

extension ArrayValue: SharedBackingArrayValue {}

/// An PostScript array value.
public struct ArrayValue: CollectionValue, VMStoredCompositeValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .array
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``access`` value.
  public private(set) var access: ObjectAccess = Self.maxAccess

  typealias StoredStorage = [VMStoredObject]
  typealias Shared = CompositeShared<StoredStorage>

  private var ref: Shared
  private let rootLease: VMRootLease
  /// The ``refRange`` value.
  public let refRange: StorageRange

  /// Creates an instance.
  public init(elements: Storage, access: ObjectAccess, vm: VM) throws {
    try elements.checkStorage(in: vm)
    let stored = elements.map(VMStoredObject.init)
    let ref = Shared(
      value: stored,
      access: access,
      vm: vm,
      chargedBytes: Self.footprint(for: stored.count),
      footprint: { Self.footprint(for: $0.count) },
      children: { $0.vmAllocations },
      snapshotCopy: { $0.map { $0.copiedForSnapshot() } },
      storedObjects: { $0 },
      identifyEdges: { $0.identifyVMEdgeSources($1) },
      clear: { $0.removeAll(keepingCapacity: false) }
    )
    ref.uncheckedRead { $0.value.identifyVMEdgeSources(ref.allocation) }
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
    self.refRange = elements.indices
    self.access = access
  }

  /// Creates an instance.
  public init(sharing: Self, subRange: SubRange) throws {
    self.ref = sharing.ref
    self.rootLease = sharing.rootLease
    self.refRange = try sharing.refRange.select(subRange: subRange, in: sharing.ref.uncheckedRead { $0.value })
    self.access = sharing.access
  }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// The ``vm`` value.
  public var vm: VM { ref.vm }
  var allocation: VMAllocation { ref.allocation }
  var allocationFootprint: Int { Self.footprint(for: ref.uncheckedRead { $0.value.count }) }

  /// The ``count`` value.
  public var count: UInt {
    UInt(ref.uncheckedRead { $0.value.distance(from: refRange.lowerBound, to: refRange.upperBound) })
  }
  /// The ``range`` value.
  public var range: SubRange { 0..<count }

  /// Performs the ``object`` operation.
  public func object(at position: UInt, for access: Object.Access = .read) throws -> Object {
    try self.access.check(access)

    return try ref.uncheckedRead { refState in
      let index = try refRange.select(subRange: position..<position + 1, in: refState.value).lowerBound
      return refState.value[index].object
    }
  }

  /// Performs the ``objects`` operation.
  public func objects(in subRange: SubRange, for access: Object.Access) throws -> ArraySlice<Object> {
    try self.access.check(access)
    return try ref.uncheckedRead { refState in
      let subRange = try refRange.select(subRange: subRange, in: refState.value)
      return ArraySlice(refState.value[subRange].map(\.object))
    }
  }

  /// Performs the ``updateObject`` operation.
  public func updateObject(_ object: Object, at position: UInt) throws {
    try access.check(.write)
    try object.checkStorage(in: ref.vm)
    return try ref.uncheckedWrite { ref in
      let index = try refRange.select(subRange: position..<position + 1, in: ref.value).lowerBound
      let stored = VMStoredObject(object)
      stored.identifyEdgeSource(self.ref.allocation)
      ref.value[index] = stored
    }
  }

  /// Performs the ``updateObjects`` operation.
  public func updateObjects(_ objects: some Collection<Object>, startingAt position: UInt) throws {
    try access.check(.write)
    try objects.checkStorage(in: ref.vm)
    return try ref.uncheckedWrite { ref in
      let range = try refRange.select(subRange: position..<position + UInt(objects.count), in: ref.value)
      let stored = objects.map(VMStoredObject.init)
      stored.identifyVMEdgeSources(self.ref.allocation)
      ref.value.replaceSubrange(range, with: stored)
    }
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object) throws -> Void) rethrows {
    let elements = ref.uncheckedRead { $0.value[refRange].map(\.object) }
    try elements.forEach(block)
  }

  func forEachBackingUnchecked(_ block: (Object) throws -> Void) rethrows {
    let elements = ref.uncheckedRead { $0.value.map(\.object) }
    try elements.forEach(block)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    forEachBackingUnchecked { $0.save(to: snapshot) }
    ref.save(to: snapshot)
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    let obj = Object(value: self, kind: kind)
    switch method {
    case .indirect:
      try access.check(.execute)
      try context.execution.push(source: obj, in: context)

    case .direct:
      context.operands.push(obj)
    }
  }

  // - MARK: Equals/Hash

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    if refRange.isEmpty, other.refRange.isEmpty {
      return true
    }
    return arrayViewIdentity == other.arrayViewIdentity
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(refRange.isEmpty)
    if !refRange.isEmpty {
      hasher.combine(arrayViewIdentity)
    }
  }

  /// A debug representation of this value.
  public var debugString: String {
    let snapshot = ref.uncheckedRead { refState in
      (elements: refState.value[refRange].map(\.object), backingCount: refState.value.count)
    }
    let logicalRange = 0..<UInt(snapshot.elements.count)
    let slice = snapshot.elements.count != snapshot.backingCount ? "[\(logicalRange)]" : ""
    return "[\(snapshot.elements.map(\.debugString).joined(separator: ", "))]\(slice)"
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    let elements = ref.uncheckedRead { $0.value[refRange].map(\.object) }
    let tokens = elements.compactMap { $0.tokenString() }
    guard tokens.count == elements.count else {
      return nil
    }
    return "[\(tokens.joined(separator: ", "))]"
  }

  func storedObject(kind: ObjectKind) -> VMStoredObject {
    let object = Object(value: self, kind: kind)
    let range = refRange
    let access = access
    return .reference(allocation: allocation, owner: ref, object: object) { [weak ref] in
      guard let ref else { return nil }
      return Object(value: Self(ref: ref, refRange: range, access: access), kind: kind)
    }
  }

  func refreshStoredEdges() {
    ref.uncheckedRead { $0.value.refreshVMEdges() }
  }

  private init(ref: Shared, refRange: StorageRange, access: ObjectAccess) {
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
    self.refRange = refRange
    self.access = access
  }

  private static func footprint(for count: Int) -> Int {
    count * 8 + 16
  }
}
