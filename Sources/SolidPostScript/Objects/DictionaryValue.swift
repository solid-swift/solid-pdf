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
public struct DictionaryValue: CompositeValue, VMStoredCompositeValue {

  /// The type used to represent ``Storage``.
  public typealias Storage = [Object: Object]

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .dictionary
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  typealias StoredStorage = [VMStoredObject: VMStoredObject]
  typealias Shared = CompositeShared<StoredStorage>

  struct PreparedMutation: Sendable {
    let revision: UInt64
    let entries: Storage
    let minimumCapacity: Int
    let allocationGrowthBytes: Int
  }

  private let ref: Shared
  private let rootLease: VMRootLease

  /// Creates an instance.
  public init(value: Storage, access: ObjectAccess, vm: VM) throws {
    let value = try Self.normalizedStorage(
      value.map { ($0.key, $0.value) },
      minimumCapacity: value.capacity,
      in: vm
    )
    self.ref = Self.makeShared(value: value, access: access, vm: vm)
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
  }

  init<S: Sequence>(entries: S, access: ObjectAccess, vm: VM) throws where S.Element == (Object, Object) {
    let value = try Self.normalizedStorage(entries, minimumCapacity: entries.underestimatedCount, in: vm)
    self.ref = Self.makeShared(value: value, access: access, vm: vm)
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
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

    self.ref = Self.makeShared(value: value, access: .unlimited, vm: .global)
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
  }

  /// Creates an instance.
  public init(sharing: Self) {
    self.ref = sharing.ref
    self.rootLease = sharing.rootLease
  }

  /// The ``access`` value.
  public var access: ObjectAccess { ref.uncheckedRead { $1 } }

  /// Performs the ``setAccess`` operation.
  public func setAccess(to access: ObjectAccess) throws {
    try ref.allocation.prepareSnapshotMutation()
    self.ref.uncheckedWrite { $0.access = access }
  }

  /// Reduces this dictionary's shared access while preserving the read-only dictionary restriction.
  public mutating func reduceAccess(to reducedAccess: ObjectAccess) throws {
    try ref.allocation.prepareSnapshotMutation()
    try ref.uncheckedWrite { state in
      try state.access.canReduce(to: reducedAccess)
      guard state.access != .readOnly || reducedAccess != .noAccess else {
        throw Error.invalidAccess
      }
      state.access = reducedAccess
    }
  }

  internal var weakRef: Weak<Shared> { Weak(value: ref) }

  /// The ``vm`` value.
  public var vm: VM { ref.vm }
  var allocation: VMAllocation { ref.allocation }
  var revision: UInt64 { ref.versionedRead { _ in () }.revision }
  var allocationFootprint: Int { Self.footprint(forCapacity: ref.uncheckedRead { $0.value.capacity }) }

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
    guard let value = try ref.read({ $0.value[VMStoredObject(key)]?.object }) else {
      throw Error.undefined
    }
    return value
  }

  /// The ``keys`` value.
  public var keys: some Collection<Object> { ref.uncheckedRead { $0.value.keys.map(\.object) } }

  /// Performs the ``object`` operation.
  public func object(forKeyIfExists key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    return try ref.read { $0.value[VMStoredObject(key)]?.object }
  }

  func objectUnchecked(forKey key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    return ref.uncheckedRead { $0.value[VMStoredObject(key)]?.object }
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
    return try ref.write { state in
      let storedKey = VMStoredObject(key)
      let storedValue = VMStoredObject(value)
      storedKey.identifyEdgeSource(self.ref.allocation)
      storedValue.identifyEdgeSource(self.ref.allocation)
      let previous = state.value.updateValue(storedValue, forKey: storedKey)?.object
      ref.allocation.updateFootprint(to: Self.footprint(forCapacity: state.value.capacity))
      return previous
    }
  }

  /// Performs the ``updateObjects`` operation.
  public func updateObjects(forKeysIn dict: DictionaryValue) throws {
    while true {
      let mutation = try prepareUpdateObjects(forKeysIn: dict)
      if try commit(mutation) {
        return
      }
    }
  }

  func prepareUpdateObject(_ value: Object, forKey key: Object) throws -> PreparedMutation {
    let key = try key.dictionaryKey
    try key.checkStorage(in: ref.vm)
    try value.checkStorage(in: ref.vm)
    return try prepareMutation(entries: [key: value])
  }

  func prepareInterpreterUpdateObject(_ value: Object, forKey key: Object) throws -> PreparedMutation {
    let key = try key.dictionaryKey
    try key.checkStorage(in: ref.vm)
    try value.checkStorage(in: ref.vm)
    return try prepareMutation(entries: [key: value], requiresWriteAccess: false)
  }

  func prepareUpdateObjects(forKeysIn dict: DictionaryValue) throws -> PreparedMutation {
    let source = try dict.ref.read { state in
      Dictionary(uniqueKeysWithValues: state.value.map { ($0.key.object, $0.value.object) })
    }
    let entries = try Self.normalizedStorage(
      source.map { ($0.key, $0.value) },
      minimumCapacity: source.capacity,
      in: ref.vm
    )
    return try prepareMutation(entries: entries)
  }

  func commit(_ mutation: PreparedMutation) throws -> Bool {
    try ref.write(ifRevision: mutation.revision) { destination in
      destination.value.reserveCapacity(mutation.minimumCapacity)
      for (key, value) in mutation.entries {
        let storedKey = VMStoredObject(key)
        let storedValue = VMStoredObject(value)
        storedKey.identifyEdgeSource(self.ref.allocation)
        storedValue.identifyEdgeSource(self.ref.allocation)
        destination.value[storedKey] = storedValue
      }
      ref.allocation.updateFootprint(to: Self.footprint(forCapacity: destination.value.capacity))
    }
  }

  /// Performs the ``removeObject`` operation.
  public func removeObject(forKey key: Object) throws -> Object? {
    let key = try key.dictionaryKey
    return try ref.write { $0.value.removeValue(forKey: VMStoredObject(key))?.object }
  }

  /// Performs the ``forEachUnchecked`` operation.
  public func forEachUnchecked(_ block: (Object, Object) throws -> Void) throws {
    let entries = ref.uncheckedRead { $0.value.map { ($0.key.object, $0.value.object) } }
    for (key, value) in entries {
      try block(key, value)
    }
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    let entries = ref.uncheckedRead { $0.value.map { ($0.key.object, $0.value.object) } }
    for (key, value) in entries {
      key.save(to: snapshot)
      value.save(to: snapshot)
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
      "[\(refState.value.map { "\($0.key.object.debugString): \($0.value.object.debugString)" }.joined(separator: ", "))]"
    }
  }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    ref.uncheckedRead { refState in
      let tokens = refState.value.flatMap { key, value in
        [key.object.tokenString(), value.object.tokenString()]
      }.compacted()
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

  private func prepareMutation(entries: Storage, requiresWriteAccess: Bool = true) throws -> PreparedMutation {
    let snapshot = try ref.versionedRead { destination in
      if requiresWriteAccess { try destination.access.check(.write) }
      let addedEntryCount = entries.keys.count { destination.value[VMStoredObject($0)] == nil }
      let minimumCapacity = destination.value.count + addedEntryCount
      var projected = destination.value
      projected.reserveCapacity(minimumCapacity)
      return (
        minimumCapacity,
        Self.footprint(forCapacity: projected.capacity) - Self.footprint(forCapacity: destination.value.capacity)
      )
    }
    return PreparedMutation(
      revision: snapshot.revision,
      entries: entries,
      minimumCapacity: snapshot.value.0,
      allocationGrowthBytes: snapshot.value.1
    )
  }

  func storedObject(kind: ObjectKind) -> VMStoredObject {
    let object = Object(value: self, kind: kind)
    return .reference(allocation: allocation, owner: ref, object: object) { [weak ref] in
      guard let ref else { return nil }
      return Object(value: Self(ref: ref), kind: kind)
    }
  }

  func refreshStoredEdges() {
    ref.uncheckedRead { state in
      state.value.keys.refreshVMEdges()
      state.value.values.refreshVMEdges()
    }
  }

  private init(ref: Shared) {
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
  }

  private static func makeShared(value: Storage, access: ObjectAccess, vm: VM) -> Shared {
    var stored = StoredStorage(minimumCapacity: value.capacity)
    for (key, value) in value {
      stored[VMStoredObject(key)] = VMStoredObject(value)
    }
    let ref = Shared(
      value: stored,
      access: access,
      vm: vm,
      chargedBytes: footprint(forCapacity: stored.capacity),
      footprint: { footprint(forCapacity: $0.capacity) },
      children: { storage in
        storage.keys.vmAllocations + storage.values.vmAllocations
      },
      snapshotCopy: { storage in
        var copy = StoredStorage(minimumCapacity: storage.capacity)
        for (key, value) in storage {
          copy[key.copiedForSnapshot()] = value.copiedForSnapshot()
        }
        return copy
      },
      storedObjects: { Array($0.keys) + Array($0.values) },
      identifyEdges: { storage, allocation in
        storage.keys.identifyVMEdgeSources(allocation)
        storage.values.identifyVMEdgeSources(allocation)
      },
      clear: { $0.removeAll(keepingCapacity: false) }
    )
    ref.uncheckedRead { state in
      state.value.keys.identifyVMEdgeSources(ref.allocation)
      state.value.values.identifyVMEdgeSources(ref.allocation)
    }
    return ref
  }

  private static func footprint(forCapacity capacity: Int) -> Int {
    capacity * 16 + 32
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
        let name = try string.readableString
        try LanguageLimits.validateName(name)
        return .literalName(name)
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
