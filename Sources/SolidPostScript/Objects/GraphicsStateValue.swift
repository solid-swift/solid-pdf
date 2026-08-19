import Foundation
import SolidRaster

extension Object {
  static func graphicsState(_ state: GraphicsCanonicalState, vm: VM) throws -> Self {
    .init(value: try GraphicsStateValue(state: state, vm: vm))
  }
}

/// A managed PostScript graphics-state object.
public struct GraphicsStateValue: CompositeValue, VMStoredCompositeValue {
  private struct Storage: Sendable {
    struct PageDeviceParameters: Sendable {
      let install: VMStoredObject
      let beginPage: VMStoredObject
      let endPage: VMStoredObject
      let policies: VMStoredObject

      init(_ parameters: PostScriptPageDeviceParameters) {
        install = VMStoredObject(parameters.install)
        beginPage = VMStoredObject(parameters.beginPage)
        endPage = VMStoredObject(parameters.endPage)
        policies = VMStoredObject(parameters.policies)
      }

      var parameters: PostScriptPageDeviceParameters {
        return PostScriptPageDeviceParameters(
          install: install.object,
          beginPage: beginPage.object,
          endPage: endPage.object,
          policies: policies.object
        )
      }

      var storedObjects: [VMStoredObject] { [install, beginPage, endPage, policies] }
    }

    var device: PostScriptDeviceRecord
    var pageDeviceParameters: PageDeviceParameters?
    var snapshot: GraphicsStateSnapshot
    var resolvedClip: RasterRegion
    var clipStack: [GraphicsClipStackEntry]
    var dashSource: VMStoredObject?
    var colorSelection: PostScriptColorSelection.Stored
    var colorComponents: [Double]
    var patternSource: VMStoredObject?
    var colorRenderingSource: VMStoredObject?
    var transferFunctionSources: [VMStoredObject?]
    var blackGenerationSource: VMStoredObject?
    var undercolorRemovalSource: VMStoredObject?
    var halftoneSource: VMStoredObject?
    var fontSource: VMStoredObject?
    var overprint: Bool
    var screenLease: ScreenLease?

    init(_ state: GraphicsCanonicalState) {
      self.device = state.device
      self.pageDeviceParameters = state.pageDeviceParameters.map(PageDeviceParameters.init)
      self.snapshot = state.snapshot
      self.resolvedClip = state.resolvedClip
      self.clipStack = state.clipStack
      self.dashSource = state.dashSource.map(VMStoredObject.init)
      self.colorSelection = PostScriptColorSelection.Stored(state.colorSelection)
      self.colorComponents = state.colorComponents
      self.patternSource = state.patternSource.map(VMStoredObject.init)
      self.colorRenderingSource = state.colorRenderingSource.map(VMStoredObject.init)
      self.transferFunctionSources = state.transferFunctionSources.map { $0.map(VMStoredObject.init) }
      self.blackGenerationSource = state.blackGenerationSource.map(VMStoredObject.init)
      self.undercolorRemovalSource = state.undercolorRemovalSource.map(VMStoredObject.init)
      self.halftoneSource = state.halftoneSource.map(VMStoredObject.init)
      self.fontSource = state.fontSource.map(VMStoredObject.init)
      self.overprint = state.overprint
      self.screenLease = state.screenLease
    }

    var canonical: GraphicsCanonicalState {
      GraphicsCanonicalState(
        device: device,
        pageDeviceParameters: pageDeviceParameters?.parameters,
        matrix: snapshot.matrix,
        path: snapshot.path,
        clip: snapshot.clip,
        paint: snapshot.paint,
        colorSelection: colorSelection.value,
        colorComponents: colorComponents,
        patternSource: patternSource?.object,
        colorRenderingSource: colorRenderingSource?.object,
        transferFunctionSources: transferFunctionSources.map { $0?.object },
        blackGenerationSource: blackGenerationSource?.object,
        undercolorRemovalSource: undercolorRemovalSource?.object,
        halftoneSource: halftoneSource?.object,
        deviceRendering: snapshot.deviceRendering,
        screenLease: screenLease,
        fontSource: fontSource?.object,
        font: snapshot.font,
        overprint: overprint,
        lineWidth: snapshot.lineWidth,
        lineCap: snapshot.lineCap,
        lineJoin: snapshot.lineJoin,
        miterLimit: snapshot.miterLimit,
        dash: snapshot.dash,
        dashSource: dashSource?.object,
        flatness: snapshot.flatness,
        strokeAdjustment: snapshot.strokeAdjustment,
        smoothness: snapshot.smoothness,
        pathBoundingBox: snapshot.pathBoundingBox,
        resolvedClip: resolvedClip,
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
      children: {
        [$0.dashSource, $0.colorRenderingSource, $0.patternSource, $0.blackGenerationSource,
          $0.undercolorRemovalSource, $0.halftoneSource, $0.fontSource].compactMap { $0?.allocation }
          + $0.transferFunctionSources.compactMap { $0?.allocation }
          + $0.colorSelection.storedObjects.compactMap(\.allocation)
          + ($0.pageDeviceParameters?.storedObjects.compactMap(\.allocation) ?? [])
      },
      snapshotCopy: { Storage($0.canonical) },
      storedObjects: {
        [$0.dashSource, $0.colorRenderingSource, $0.patternSource, $0.blackGenerationSource,
          $0.undercolorRemovalSource, $0.halftoneSource, $0.fontSource].compactMap { $0 }
          + $0.transferFunctionSources.compactMap { $0 }
          + $0.colorSelection.storedObjects
          + ($0.pageDeviceParameters?.storedObjects ?? [])
      },
      identifyEdges: { storage, allocation in
        storage.dashSource?.identifyEdgeSource(allocation)
        storage.colorSelection.identifyEdges(from: allocation)
        storage.colorRenderingSource?.identifyEdgeSource(allocation)
        storage.transferFunctionSources.forEach { $0?.identifyEdgeSource(allocation) }
        storage.blackGenerationSource?.identifyEdgeSource(allocation)
        storage.undercolorRemovalSource?.identifyEdgeSource(allocation)
        storage.halftoneSource?.identifyEdgeSource(allocation)
        storage.fontSource?.identifyEdgeSource(allocation)
        storage.patternSource?.identifyEdgeSource(allocation)
        storage.pageDeviceParameters?.storedObjects.forEach { $0.identifyEdgeSource(allocation) }
      },
      clear: {
        let state = GraphicsCanonicalState.initial(for: .letter)
        $0.device = state.device
        $0.snapshot = state.snapshot
        $0.resolvedClip = RasterRegion()
        $0.clipStack.removeAll()
        $0.dashSource = nil
        $0.colorSelection = PostScriptColorSelection.Stored(.direct(.deviceGray(nil)))
        $0.colorComponents = [0]
        $0.colorRenderingSource = nil
        $0.transferFunctionSources = [nil, nil, nil, nil]
        $0.blackGenerationSource = nil
        $0.undercolorRemovalSource = nil
        $0.halftoneSource = nil
        $0.fontSource = nil
        $0.patternSource = nil
        $0.pageDeviceParameters = nil
        $0.overprint = false
      }
    )
    storage.dashSource?.identifyEdgeSource(ref.allocation)
    storage.colorSelection.identifyEdges(from: ref.allocation)
    storage.colorRenderingSource?.identifyEdgeSource(ref.allocation)
    storage.transferFunctionSources.forEach { $0?.identifyEdgeSource(ref.allocation) }
    storage.blackGenerationSource?.identifyEdgeSource(ref.allocation)
    storage.undercolorRemovalSource?.identifyEdgeSource(ref.allocation)
    storage.halftoneSource?.identifyEdgeSource(ref.allocation)
    storage.fontSource?.identifyEdgeSource(ref.allocation)
    storage.patternSource?.identifyEdgeSource(ref.allocation)
    storage.pageDeviceParameters?.storedObjects.forEach { $0.identifyEdgeSource(ref.allocation) }
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
      storage.colorSelection.identifyEdges(from: ref.allocation)
      storage.colorRenderingSource?.identifyEdgeSource(ref.allocation)
      storage.transferFunctionSources.forEach { $0?.identifyEdgeSource(ref.allocation) }
      storage.blackGenerationSource?.identifyEdgeSource(ref.allocation)
      storage.undercolorRemovalSource?.identifyEdgeSource(ref.allocation)
      storage.halftoneSource?.identifyEdgeSource(ref.allocation)
      storage.fontSource?.identifyEdgeSource(ref.allocation)
      storage.patternSource?.identifyEdgeSource(ref.allocation)
      storage.pageDeviceParameters?.storedObjects.forEach { $0.identifyEdgeSource(ref.allocation) }
      $0.value = storage
    }
    allocation.updateFootprint(to: newFootprint)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    state().dashSource?.save(to: snapshot)
    state().colorSelection.retainedObjects.forEach { $0.save(to: snapshot) }
    state().colorRenderingSource?.save(to: snapshot)
    state().transferFunctionSources.forEach { $0?.save(to: snapshot) }
    state().blackGenerationSource?.save(to: snapshot)
    state().undercolorRemovalSource?.save(to: snapshot)
    state().halftoneSource?.save(to: snapshot)
    state().fontSource?.save(to: snapshot)
    state().patternSource?.save(to: snapshot)
    if let parameters = state().pageDeviceParameters {
      parameters.install.save(to: snapshot)
      parameters.beginPage.save(to: snapshot)
      parameters.endPage.save(to: snapshot)
      parameters.policies.save(to: snapshot)
    }
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
    ref.uncheckedRead { $0.value.colorSelection.refreshEdges() }
    ref.uncheckedRead { $0.value.colorRenderingSource?.refreshEdge() }
    ref.uncheckedRead { $0.value.transferFunctionSources.forEach { $0?.refreshEdge() } }
    ref.uncheckedRead { $0.value.blackGenerationSource?.refreshEdge() }
    ref.uncheckedRead { $0.value.undercolorRemovalSource?.refreshEdge() }
    ref.uncheckedRead { $0.value.halftoneSource?.refreshEdge() }
    ref.uncheckedRead { $0.value.fontSource?.refreshEdge() }
    ref.uncheckedRead { $0.value.pageDeviceParameters?.storedObjects.forEach { $0.refreshEdge() } }
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
    let clipStackTrapezoids = storage.clipStack.reduce(0) {
      add($0, $1.region.trapezoids.count)
    }
    let colorBytes = multiply(storage.colorComponents.count, MemoryLayout<Double>.stride)
    return add(
      add(64, multiply(storage.snapshot.path.elements.count, 56)),
      add(
        multiply(storage.snapshot.clip.constraints.count, 64),
        add(
          multiply(storage.resolvedClip.trapezoids.count, 56),
          add(
            multiply(storage.clipStack.count, 32),
            add(multiply(clipStackTrapezoids, 56), colorBytes)
          )
        )
      )
    )
  }
}
