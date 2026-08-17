import Foundation

extension Object {
  static func graphicsState(_ state: GraphicsCanonicalState, vm: VM) throws -> Self {
    .init(value: try GraphicsStateValue(state: state, vm: vm))
  }
}

/// A managed PostScript graphics-state object.
public struct GraphicsStateValue: CompositeValue, VMStoredCompositeValue {
  private struct Storage: Sendable {
    var snapshot: GraphicsStateSnapshot
    var clipStack: [GraphicsClip]
    var dashSource: VMStoredObject?

    init(_ state: GraphicsCanonicalState) {
      self.snapshot = state.snapshot
      self.clipStack = state.clipStack
      self.dashSource = state.dashSource.map(VMStoredObject.init)
    }

    var canonical: GraphicsCanonicalState {
      GraphicsCanonicalState(
        matrix: snapshot.matrix,
        path: snapshot.path,
        clip: snapshot.clip,
        paint: snapshot.paint,
        lineWidth: snapshot.lineWidth,
        lineCap: snapshot.lineCap,
        lineJoin: snapshot.lineJoin,
        miterLimit: snapshot.miterLimit,
        dash: snapshot.dash,
        dashSource: dashSource?.object,
        clipStack: clipStack
      )
    }
  }

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .graphicsState
  /// Graphics-state objects are literal by default.
  public static let defaultKind: ObjectKind = .literal
  /// Graphics-state objects do not expose access-changing operators.
  public private(set) var access: ObjectAccess = .unlimited

  private let ref: CompositeShared<Storage>
  private let rootLease: VMRootLease

  init(state: GraphicsCanonicalState, vm: VM) throws {
    try state.checkStorage(in: vm)
    let storage = Storage(state)
    let ref = CompositeShared(
      value: storage,
      access: .unlimited,
      vm: vm,
      chargedBytes: Self.footprint(storage),
      footprint: Self.footprint,
      children: { $0.dashSource?.allocation.map { [$0] } ?? [] },
      snapshotCopy: { Storage($0.canonical) },
      storedObjects: { $0.dashSource.map { [$0] } ?? [] },
      identifyEdges: { storage, allocation in storage.dashSource?.identifyEdgeSource(allocation) },
      clear: {
        $0.snapshot = GraphicsCanonicalState.initial(for: .letter).snapshot
        $0.clipStack.removeAll()
        $0.dashSource = nil
      }
    )
    storage.dashSource?.identifyEdgeSource(ref.allocation)
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
  }

  private init(ref: CompositeShared<Storage>, access: ObjectAccess) {
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
    self.access = access
  }

  /// The virtual-memory domain containing this graphics state.
  public var vm: VM { ref.vm }
  var allocation: VMAllocation { ref.allocation }
  var allocationFootprint: Int { ref.uncheckedRead { Self.footprint($0.value) } }

  static func footprint(_ state: GraphicsCanonicalState) -> Int {
    footprint(Storage(state))
  }

  /// Reduces the view's access attribute.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  func state() -> GraphicsCanonicalState {
    ref.uncheckedRead { $0.value.canonical }
  }

  func update(_ state: GraphicsCanonicalState, context: isolated Context) throws {
    try state.checkStorage(in: vm)
    let storage = Storage(state)
    let oldFootprint = allocationFootprint
    let newFootprint = Self.footprint(storage)
    try context.preflightAllocation(bytes: max(0, newFootprint - oldFootprint), vm: vm)
    try ref.write {
      storage.dashSource?.identifyEdgeSource(ref.allocation)
      $0.value = storage
    }
    allocation.updateFootprint(to: newFootprint)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    state().dashSource?.save(to: snapshot)
    ref.save(to: snapshot)
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    context.operands.push(Object(value: self, kind: kind))
  }

  /// Returns whether two graphics-state objects have the same identity.
  public func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else { return false }
    return allocation.identity == other.allocation.identity
  }

  /// Hashes the graphics-state identity.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(allocation.identity)
  }

  /// A debug representation of this value.
  public var debugString: String { "-gstate-" }

  func storedObject(kind: ObjectKind) -> VMStoredObject {
    let object = Object(value: self, kind: kind)
    let access = access
    return .reference(allocation: allocation, owner: ref, object: object) { [weak ref] in
      guard let ref else { return nil }
      return Object(value: Self(ref: ref, access: access), kind: kind)
    }
  }

  func refreshStoredEdges() {
    ref.uncheckedRead { $0.value.dashSource?.refreshEdge() }
  }

  private static func footprint(_ storage: Storage) -> Int {
    func multiply(_ lhs: Int, _ rhs: Int) -> Int {
      let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
      return overflow ? .max : value
    }
    func add(_ lhs: Int, _ rhs: Int) -> Int {
      let (value, overflow) = lhs.addingReportingOverflow(rhs)
      return overflow ? .max : value
    }
    return add(
      add(64, multiply(storage.snapshot.path.elements.count, 56)),
      add(multiply(storage.snapshot.clip.constraints.count, 64), multiply(storage.clipStack.count, 32))
    )
  }
}
