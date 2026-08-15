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
}

/// A PostScript packed array value.
public struct PackedArrayValue: CollectionValue, CompositeValue {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .packedArray
  /// The ``maxAccess`` value.
  public static let maxAccess: ObjectAccess = .readOnly
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .executable

  /// The ``access`` value.
  public private(set) var access: ObjectAccess = Self.maxAccess
  /// The ``vm`` value.
  public let vm: VM

  /// The ``elements`` value.
  public let elements: [Object]

  /// Creates an instance.
  public init(elements: [Object]) {
    self.elements = elements
    self.vm = .local
  }

  /// Creates an instance in the specified virtual-memory domain.
  public init(elements: [Object], vm: VM) throws {
    try elements.checkStorage(in: vm)
    self.elements = elements
    self.vm = vm
  }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// The ``count`` value.
  public var count: UInt { UInt(elements.count) }
  /// The ``range`` value.
  public var range: SubRange { 0..<count }

  /// Performs the ``object`` operation.
  public func object(at position: UInt, for access: Object.Access) throws -> Object {
    try self.access.check(access)
    let index = try elements.indices.select(subRange: position..<position + 1, in: elements).lowerBound
    return elements[index]
  }

  /// Performs the ``objects`` operation.
  public func objects(in subRange: SubRange, for access: Object.Access) throws -> ArraySlice<Object> {
    try self.access.check(access)
    let subRange = try elements.indices.select(subRange: subRange, in: elements)
    return elements[subRange]
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object) throws -> Void) rethrows {
    try elements.forEach(block)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    for element in elements {
      element.save(to: snapshot)
    }
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
    try context.execution.push(source: Object(value: self, kind: kind), in: context)
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return elements == other.elements
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(elements)
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
