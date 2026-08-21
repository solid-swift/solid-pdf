import Foundation

extension Object {
  static func fontID(identifier: GraphicsFontIdentifier, providerFace: FontProviderFace?, vm: VM) -> Self {
    .init(value: FontIDValue(identifier: identifier, providerFace: providerFace, vm: vm))
  }
}

/// An opaque identifier associated with one defined PostScript font instance.
public struct FontIDValue: CompositeValue, VMStoredCompositeValue {
  private final class Storage: Sendable {
    let identifier: GraphicsFontIdentifier
    let providerFace: FontProviderFace?
    let allocation: VMAllocation

    init(identifier: GraphicsFontIdentifier, providerFace: FontProviderFace?, vm: VM) {
      self.identifier = identifier
      self.providerFace = providerFace
      self.allocation = VMAllocationContext.allocation(in: vm, bytes: 32)
      self.allocation.attach(owner: self)
    }
  }

  /// The PostScript type represented by an FID.
  public static let objectType: ObjectType = .fontID
  /// Font identifiers are literal objects.
  public static let defaultKind: ObjectKind = .literal

  private let storage: Storage
  private let rootLease: VMRootLease

  /// The access permitted for this opaque value.
  public private(set) var access: ObjectAccess = .noAccess

  init(identifier: GraphicsFontIdentifier, providerFace: FontProviderFace?, vm: VM) {
    let storage = Storage(identifier: identifier, providerFace: providerFace, vm: vm)
    self.storage = storage
    self.rootLease = VMRootLease(allocation: storage.allocation, owner: storage)
  }

  private init(storage: Storage, access: ObjectAccess) {
    self.storage = storage
    self.rootLease = VMRootLease(allocation: storage.allocation, owner: storage)
    self.access = access
  }

  /// The VM domain containing this identifier.
  public var vm: VM { storage.allocation.vm }
  var allocation: VMAllocation { storage.allocation }
  var allocationFootprint: Int { 32 }
  var identifier: GraphicsFontIdentifier { storage.identifier }
  var providerFace: FontProviderFace? { storage.providerFace }

  /// Reduces the view's access.
  public mutating func setAccess(to access: ObjectAccess) throws {
    try self.access.canReduce(to: access)
    self.access = access
  }

  /// Saves this immutable value by identity.
  public func save(to snapshot: Snapshot.Builder) {}

  /// Pushes this opaque identifier when executed.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    context.operands.push(.init(value: self, kind: kind))
  }

  /// Compares font identifiers by allocation identity.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else { return false }
    return allocation.identity == other.allocation.identity
  }

  /// Hashes the allocation identity.
  public func hash(into hasher: inout Hasher) { hasher.combine(allocation.identity) }

  /// An opaque debugging representation.
  public var debugString: String { "--fontid--" }

  func storedObject(kind: ObjectKind) -> VMStoredObject {
    let object = Object(value: self, kind: kind)
    return .reference(allocation: allocation, owner: storage, object: object) { [weak storage] in
      guard let storage else { return nil }
      return Object(value: Self(storage: storage, access: .noAccess), kind: kind)
    }
  }
}

extension FontIDValue: SnapshotIdentifiableValue {
  var snapshotIdentity: ObjectIdentifier { allocation.identity }
}
