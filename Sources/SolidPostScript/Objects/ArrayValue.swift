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

/// An PostScript array value.
public struct ArrayValue: CollectionValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .array
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``access`` value.
  public private(set) var access: ObjectAccess = Self.maxAccess

  typealias Shared = CompositeShared<Storage>

  private var ref: Shared
  /// The ``refRange`` value.
  public let refRange: StorageRange

  /// Creates an instance.
  public init(elements: Storage, access: ObjectAccess, vm: VM) throws {
    try elements.checkStorage(in: vm)
    self.ref = Shared(value: elements, access: access, vm: vm)
    self.refRange = elements.indices
    self.access = access
  }

  /// Creates an instance.
  public init(sharing: Self, subRange: SubRange) throws {
    self.ref = sharing.ref
    self.refRange = try sharing.refRange.select(subRange: subRange, in: sharing.ref.uncheckedRead { $0.value })
    self.access = sharing.access
  }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// The ``vm`` value.
  public var vm: VM { ref.vm }

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
      return refState.value[index]
    }
  }

  /// Performs the ``objects`` operation.
  public func objects(in subRange: SubRange, for access: Object.Access) throws -> ArraySlice<Object> {
    try self.access.check(access)
    return try ref.uncheckedRead { refState in
      let subRange = try refRange.select(subRange: subRange, in: refState.value)
      return refState.value[subRange]
    }
  }

  /// Performs the ``updateObject`` operation.
  public func updateObject(_ object: Object, at position: UInt) throws {
    try access.check(.write)
    try object.checkStorage(in: ref.vm)
    return try ref.uncheckedWrite { ref in
      let index = try refRange.select(subRange: position..<position + 1, in: ref.value).lowerBound
      ref.value[index] = object
    }
  }

  /// Performs the ``updateObjects`` operation.
  public func updateObjects(_ objects: some Collection<Object>, startingAt position: UInt) throws {
    try access.check(.write)
    try objects.checkStorage(in: ref.vm)
    return try ref.uncheckedWrite { ref in
      let range = try refRange.select(subRange: position..<position + UInt(objects.count), in: ref.value)
      ref.value.replaceSubrange(range, with: objects)
    }
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object) throws -> Void) rethrows {
    let elements = ref.uncheckedRead { $0.value }
    try elements.forEach(block)
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
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
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
    return ref === other.ref
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(ref))
  }

  /// A debug representation of this value.
  public var debugString: String {
    ref.uncheckedRead { refState in
      let slice = range.count != refState.value.count ? "[\(range)]" : ""
      return "[\(refState.value[refRange].map(\.debugString).joined(separator: ", "))]\(slice)"
    }
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    ref.uncheckedRead { refState in
      let elements = refState.value[refRange]
      let tokens = elements.compactMap { $0.tokenString() }
      guard tokens.count == elements.count else {
        return nil
      }
      return "[\(tokens.joined(separator: ", "))]"
    }
  }
}
