//
//  Object.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// A typed PostScript object with its value and execution kind.
public struct Object: Equatable, Hashable, Sendable {

  /// An PostScript access.
  public enum Access {
    case read
    case write
    case execute
  }

  /// An PostScript access method.
  public enum AccessMethod {
    case indirect
    case direct
  }

  /// The ``type`` value.
  public let type: ObjectType
  /// The ``kind`` value.
  public var kind: ObjectKind

  /// The ``value`` value.
  public let value: any ObjectValue

  init(value: ObjectValue, kind: ObjectKind? = nil) {
    let valueType = Swift.type(of: value)
    self.type = valueType.objectType
    self.kind = kind ?? valueType.defaultKind
    self.value = value
  }

  /// Performs the ``value`` operation.
  public func value<V>(as: V.Type) throws -> V {
    guard let value = value as? V else {
      throw Error.typeCheck
    }
    return value
  }

  func checkStorage(in containerVM: VM) throws {
    guard let composite = value as? any CompositeValue else {
      return
    }

    if containerVM == .global && composite.vm == .local {
      throw Error.invalidAccess
    }
  }

  func save(to snapshot: Snapshot.Builder) {
    snapshot.save(self)
  }

  func execute(context: isolated Context, method: AccessMethod) throws {
    try context.execute(object: self, method: method)
  }

  func makeIterator(context: isolated Context) throws -> ObjectIterator {
    guard let source = value as? any ObjectSource else {
      return SingleObjectIterator(object: self)
    }
    return try source.makeIterator(context: context)
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    if let numeric = value as? NumericConvertible {
      hasher.combine(ObjectType.integer)
      hasher.combine(numeric.real)
      return
    }
    hasher.combine(type)
    value.hash(into: &hasher)
  }

  /// Performs the ``lhs`` operation.
  public static func == (lhs: Object, rhs: Object) -> Bool {
    do {
      return try lhs.value.equals(rhs.value)
    } catch {
      return false
    }
  }

  /// A debug representation of this value.
  public var debugString: String {
    "<\(type)| \(value.debugString)>"
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString() -> String? {
    value.tokenString(kind: kind)
  }

  /// The value's printable string representation, when available.
  public var valueString: String? {
    value.valueString
  }

}
