//
//  DictionaryValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

extension Object: ExpressibleByDictionaryLiteral {

  /// Creates an instance.
  public init(dictionaryLiteral elements: (Object, Object)...) {
    self.init(
      value: neverThrow(try DictionaryValue(entries: elements, access: .unlimited, vm: .local)),
      kind: .literal
    )
  }

  /// Performs the ``dictionary`` operation.
  public static func dictionary(_ value: DictionaryValue.Storage, access: ObjectAccess, vm: VM, kind: ObjectKind) throws
    -> Self
  {
    Self(value: try DictionaryValue(value: value, access: access, vm: vm), kind: kind)
  }

  /// Performs the ``dictionary`` operation.
  public static func dictionary(
    uniqueKeysWithValues: some Sequence<(Object, Object)>,
    access: ObjectAccess,
    vm: VM,
    kind: ObjectKind
  ) throws -> Self {
    Self(
      value: try DictionaryValue(entries: uniqueKeysWithValues, access: access, vm: vm),
      kind: kind
    )
  }

  /// Performs the ``dictionary`` operation.
  public static func dictionary(sharing: DictionaryValue, kind: ObjectKind) -> Self {
    Self(value: sharing, kind: kind)
  }
}

/// A PostScript dictionary value.
public struct DictionaryValue: CompositeValue {

  /// The type used to represent ``Storage``.
  public typealias Storage = [Object: Object]

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .dictionary
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  typealias Shared = CompositeShared<Storage>

  private let ref: Shared

  /// Creates an instance.
  public init(value: Storage, access: ObjectAccess, vm: VM) throws {
    let value = try Self.normalizedStorage(
      value.map { ($0.key, $0.value) },
      minimumCapacity: value.capacity,
      in: vm
    )
    self.ref = Shared(value: value, access: access, vm: vm)
  }

  init<S: Sequence>(entries: S, access: ObjectAccess, vm: VM) throws where S.Element == (Object, Object) {
    let value = try Self.normalizedStorage(entries, minimumCapacity: entries.underestimatedCount, in: vm)
    self.ref = Shared(value: value, access: access, vm: vm)
  }

  // The system dictionary is the sole global container permitted to retain named local dictionaries.
  init(systemDictionaryValue value: Storage, localDictionaryKeys: Set<Object>) throws {
    let value = try Self.normalizedStorage(
      value.map { ($0.key, $0.value) },
      minimumCapacity: value.capacity,
      in: .local
    )
    let localDictionaryKeys = try Set(localDictionaryKeys.map { try $0.dictionaryKey })

    for (key, object) in value {
      try key.checkStorage(in: .global)

      if localDictionaryKeys.contains(key) {
        guard let dictionary = object.value as? DictionaryValue, dictionary.vm == .local else {
          throw Error.invalidAccess
        }
      } else {
        try object.checkStorage(in: .global)
      }
    }

    self.ref = Shared(value: value, access: .unlimited, vm: .global)
  }

  /// Creates an instance.
  public init(sharing: Self) {
    self.ref = sharing.ref
  }

  /// The ``access`` value.
  public var access: ObjectAccess { ref.uncheckedRead { $1 } }

  /// Performs the ``setAccess`` operation.
  public func setAccess(to access: ObjectAccess) throws {
    self.ref.uncheckedWrite { $0.access = access }
  }

  internal var weakRef: Weak<Shared> { Weak(value: ref) }

  /// The ``vm`` value.
  public var vm: VM { ref.vm }

  /// The ``count`` value.
  public var count: UInt { UInt(ref.uncheckedRead { $0.value.count }) }
  /// The ``capacity`` value.
  public var capacity: UInt { UInt(ref.uncheckedRead { $0.value.capacity }) }

  /// Performs the ``objectValue`` operation.
  public func objectValue<V>(forKey key: Object, as: V.Type = V.self) throws -> V {
    guard let value = try object(forKeyIfExists: key) else {
      throw Error.undefined
    }
    return try value.value(as: V.self)
  }

  /// Performs the ``objectValue`` operation.
  public func objectValue<V>(forKeyIfExists key: Object, as: V.Type = V.self) throws -> V? {
    guard let value = try object(forKeyIfExists: key) else {
      return nil
    }
    return try value.value(as: V.self)
  }

  /// Performs the ``object`` operation.
  public func object(forKey key: Object) throws -> Object {
    let key = try key.dictionaryKey
    guard let value = try ref.read({ $0.value[key] }) else {
      throw Error.undefined
    }
    return value
  }

  /// The ``keys`` value.
  public var keys: some Collection<Object> { ref.uncheckedRead { $0.value.keys } }

  /// Performs the ``object`` operation.
  public func object(forKeyIfExists key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    return try ref.read { $0.value[key] }
  }

  /// Performs the ``updateObject`` operation.
  @discardableResult
  public func updateObject(_ value: Object, forKey key: Object) throws -> Object? {
    return try setObject(value, forKey: key)
  }

  /// Performs the ``setObject`` operation.
  @discardableResult
  public func setObject(_ value: Object, forKey key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    try key.checkStorage(in: ref.vm)
    try value.checkStorage(in: ref.vm)
    return try ref.write { $0.value.updateValue(value, forKey: key) }
  }

  /// Performs the ``updateObjects`` operation.
  public func updateObjects(forKeysIn dict: DictionaryValue) throws {
    let source = try dict.ref.read { $0.value }
    let normalizedSource = try Self.normalizedStorage(
      source.map { ($0.key, $0.value) },
      minimumCapacity: source.capacity,
      in: ref.vm
    )

    try ref.write { destination in
      for (key, value) in normalizedSource {
        destination.value[key] = value
      }
    }
  }

  /// Performs the ``removeObject`` operation.
  public func removeObject(forKey key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    return try ref.write { $0.value.removeValue(forKey: key) }
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object, Object) throws -> Void) throws {
    let entries = try ref.read { $0.value }
    try entries.forEach(block)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    let entries = ref.uncheckedRead { $0.value }
    for entry in entries {
      entry.key.save(to: snapshot)
      entry.value.save(to: snapshot)
    }
    ref.save(to: snapshot)
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    try access.check(.execute)
    context.operands.push(.init(value: self, kind: kind))
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
    ref.uncheckedRead { refState in
      "[\(refState.value.map { "\($0.key.debugString): \($0.value.debugString)" }.joined(separator: ", "))]"
    }
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    ref.uncheckedRead { refState in
      let tokens = refState.value.flatMap { key, value in [key.tokenString(), value.tokenString()] }.compacted()
      guard tokens.count == refState.value.count / 2 else {
        return nil
      }
      return "<< \(tokens.joined(separator: " ")) >>"
    }
  }

  private static func normalizedStorage<S: Sequence>(
    _ entries: S,
    minimumCapacity: Int,
    in vm: VM
  ) throws -> Storage where S.Element == (Object, Object) {
    var normalized = Storage(minimumCapacity: minimumCapacity)
    for (key, value) in entries {
      let key = try key.dictionaryKey
      try key.checkStorage(in: vm)
      try value.checkStorage(in: vm)
      normalized[key] = value
    }
    return normalized
  }
}

extension DictionaryValue: SnapshotIdentifiableValue {

  var snapshotIdentity: ObjectIdentifier { ObjectIdentifier(ref) }

}

extension Object {

  fileprivate var dictionaryKey: Object {
    get throws {
      switch value {
      case is NullValue:
        throw Error.typeCheck
      case let string as StringValue:
        try string.access.check(.read)
        return .literalName(string.string)
      default:
        return self
      }
    }
  }

}

extension Dictionary where Key == Object, Value == Object {

  internal func checkStorage(in vm: VM) throws {
    for (key, value) in self {
      try key.checkStorage(in: vm)
      try value.checkStorage(in: vm)
    }
  }
}
