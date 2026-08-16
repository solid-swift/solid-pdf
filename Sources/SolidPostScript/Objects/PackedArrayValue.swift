//
//  PackedArrayValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

extension Object {

  /// Performs the ``packedArray`` operation.
  public static func packedArray(_ items: some Collection<Object>, kind: ObjectKind) -> Self {
    Self(value: PackedArrayValue(elements: Array(items)), kind: kind)
  }

  /// Creates a packed array in the specified virtual-memory domain.
  public static func packedArray(_ items: some Collection<Object>, vm: VM, kind: ObjectKind) throws -> Self {
    Self(value: try PackedArrayValue(elements: Array(items), vm: vm), kind: kind)
  }

  /// Performs the ``packedArray`` operation.
  public static func packedArray(_ array: PackedArrayValue, kind: ObjectKind) -> Self {
    Self(value: array, kind: kind)
  }

  static func packedArray(
    sharing array: PackedArrayValue,
    subRange: PackedArrayValue.SubRange,
    kind: ObjectKind
  ) throws -> Self {
    Self(value: try PackedArrayValue(sharing: array, subRange: subRange), kind: kind)
  }
}

extension PackedArrayValue: SnapshotIdentifiableValue {

  var snapshotIdentity: ObjectIdentifier { ObjectIdentifier(ref) }

}

/// An immutable PostScript packed-array value.
public struct PackedArrayValue: CollectionValue, CompositeValue, VMAllocatedCompositeValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .packedArray
  /// The ``maxAccess`` value.
  public static let maxAccess: ObjectAccess = .readOnly
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .executable

  /// The ``access`` value.
  public private(set) var access: ObjectAccess = Self.maxAccess

  typealias Shared = CompositeShared<Storage>

  private let ref: Shared
  let refRange: StorageRange

  /// The packed array's elements.
  public var elements: [Object] { ref.uncheckedRead { Array($0.value[refRange]) } }

  /// Creates an instance.
  public init(elements: [Object]) {
    self.ref = Shared(value: elements, access: Self.maxAccess, vm: .local)
    self.refRange = elements.indices
  }

  /// Creates an instance in the specified virtual-memory domain.
  public init(elements: [Object], vm: VM) throws {
    try elements.checkStorage(in: vm)
    self.ref = Shared(value: elements, access: Self.maxAccess, vm: vm)
    self.refRange = elements.indices
  }

  init(sharing: Self, subRange: SubRange) throws {
    self.ref = sharing.ref
    self.refRange = try sharing.refRange.select(subRange: subRange, in: sharing.ref.uncheckedRead { $0.value })
    self.access = sharing.access
  }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// The virtual-memory domain containing this packed array.
  public var vm: VM { ref.vm }
  var allocation: VMAllocation { ref.allocation }

  /// The ``count`` value.
  public var count: UInt { UInt(refRange.count) }
  /// The ``range`` value.
  public var range: SubRange { 0..<count }

  /// Performs the ``object`` operation.
  public func object(at position: UInt, for access: Object.Access) throws -> Object {
    try self.access.check(access)
    return try ref.uncheckedRead { state in
      let index = try refRange.select(subRange: position..<position + 1, in: state.value).lowerBound
      return state.value[index]
    }
  }

  /// Performs the ``objects`` operation.
  public func objects(in subRange: SubRange, for access: Object.Access) throws -> ArraySlice<Object> {
    try self.access.check(access)
    return try ref.uncheckedRead { state in
      let selected = try refRange.select(subRange: subRange, in: state.value)
      return state.value[selected]
    }
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object) throws -> Void) rethrows {
    let elements = ref.uncheckedRead { Array($0.value[refRange]) }
    try elements.forEach(block)
  }

  func replaceElementsForBinding(_ elements: [Object]) throws {
    guard elements.count == refRange.count else { throw Error.rangeCheck }
    try elements.checkStorage(in: vm)
    ref.uncheckedWrite { $0.value.replaceSubrange(refRange, with: elements) }
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    let elements = ref.uncheckedRead { $0.value }
    for element in elements {
      element.save(to: snapshot)
    }
    ref.save(to: snapshot)
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    let object = Object(value: self, kind: kind)
    switch method {
    case .indirect:
      try access.check(.execute)
      try context.execution.push(source: object, in: context)

    case .direct:
      context.operands.push(object)
    }
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return ref === other.ref
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(ref))
  }

  /// A debug representation of this value.
  public var debugString: String {
    return "#[\(elements.map(\.debugString).joined(separator: ", "))]"
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    let tokens = elements.compactMap { $0.tokenString() }
    guard tokens.count == elements.count else {
      return nil
    }
    return "[\(tokens.joined(separator: ", "))]"
  }
}
