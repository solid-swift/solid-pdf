import Foundation

/// A language-visible color space paired with the route selected for device realization.
struct PostScriptColorSelection: Sendable {
  indirect enum Route: Sendable, Hashable {
    case colorSpace(PostScriptColorSpace)
    case indexed(base: Self, maximumIndex: Int, lookup: Object)
    case directColorants(space: GraphicsColorSpaceDescription, names: [String])
    case alternative(
      space: GraphicsColorSpaceDescription,
      names: [String],
      transform: Object,
      colorSpace: Self
    )
    case pattern(underlying: Self?)

    var componentCount: Int {
      switch self {
      case .colorSpace(let colorSpace): colorSpace.componentCount
      case .indexed: 1
      case .directColorants(_, let names): names.count
      case .alternative(_, let names, _, _): names.count
      case .pattern(let underlying): underlying?.componentCount ?? 0
      }
    }

    var retainedObjects: [Object] {
      switch self {
      case .colorSpace(let colorSpace): colorSpace.retainedObjects
      case .indexed(let base, _, let lookup): base.retainedObjects + [lookup]
      case .directColorants: []
      case .alternative(_, _, let transform, let colorSpace):
        colorSpace.retainedObjects + [transform]
      case .pattern(let underlying): underlying?.retainedObjects ?? []
      }
    }
  }

  let source: PostScriptColorSpace
  let route: Route

  var retainedObjects: [Object] { source.retainedObjects + route.retainedObjects }

  var cacheFingerprint: Int {
    var hasher = Hasher()
    hasher.combine(source)
    hasher.combine(route)
    for object in retainedObjects {
      hasher.combine(Self.revision(of: object))
    }
    return hasher.finalize()
  }

  var hasIdentityDeviceRoute: Bool {
    switch (source, route) {
    case (.deviceGray, .colorSpace(.deviceGray)),
         (.deviceRGB, .colorSpace(.deviceRGB)),
         (.deviceCMYK, .colorSpace(.deviceCMYK)):
      true
    default:
      false
    }
  }

  var patternUnderlyingSelection: Self? {
    guard case .pattern(_, let underlyingSource) = source,
      let underlyingSource,
      case .pattern(let underlyingRoute) = route,
      let underlyingRoute
    else { return nil }
    return Self(source: underlyingSource, route: underlyingRoute)
  }

  static func direct(
    _ source: PostScriptColorSpace,
    availableColorants: Set<String> = []
  ) -> Self {
    Self(
      source: source,
      route: directRoute(for: source, availableColorants: availableColorants)
    )
  }

  private static func directRoute(
    for source: PostScriptColorSpace,
    availableColorants: Set<String>
  ) -> Route {
    switch source {
    case .deviceGray, .deviceRGB, .deviceCMYK, .cieA, .cieABC, .cieDEF, .cieDEFG:
      return .colorSpace(source)
    case .indexed(_, let base, let maximumIndex, let lookup):
      return .indexed(
        base: directRoute(for: base, availableColorants: availableColorants),
        maximumIndex: maximumIndex,
        lookup: lookup
      )
    case .separation(_, let name, let alternative, let transform):
      if name == "All" || name == "None" || availableColorants.contains(name) {
        return .directColorants(space: source.description, names: [name])
      }
      return .alternative(
        space: source.description,
        names: [name],
        transform: transform,
        colorSpace: directRoute(for: alternative, availableColorants: availableColorants)
      )
    case .deviceN(_, let names, let alternative, let transform):
      if names.allSatisfy(availableColorants.contains) {
        return .directColorants(space: source.description, names: names)
      }
      return .alternative(
        space: source.description,
        names: names,
        transform: transform,
        colorSpace: directRoute(for: alternative, availableColorants: availableColorants)
      )
    case .pattern(_, let underlying):
      return .pattern(
        underlying: underlying.map { directRoute(for: $0, availableColorants: availableColorants) }
      )
    }
  }

  private static func revision(of object: Object) -> UInt64 {
    switch object.value {
    case let value as ArrayValue: value.revision
    case let value as PackedArrayValue: value.revision
    case let value as DictionaryValue: value.revision
    default: 0
    }
  }
}

extension PostScriptColorSelection {
  struct Stored: Sendable {
    indirect enum Route: Sendable {
      case colorSpace(VMStoredColorSpace)
      case indexed(base: Self, maximumIndex: Int, lookup: VMStoredObject)
      case directColorants(space: GraphicsColorSpaceDescription, names: [String])
      case alternative(
        space: GraphicsColorSpaceDescription,
        names: [String],
        transform: VMStoredObject,
        colorSpace: Self
      )
      case pattern(underlying: Self?)

      init(_ route: PostScriptColorSelection.Route) {
        switch route {
        case .colorSpace(let colorSpace):
          self = .colorSpace(VMStoredColorSpace(colorSpace))
        case .indexed(let base, let maximumIndex, let lookup):
          self = .indexed(
            base: Self(base),
            maximumIndex: maximumIndex,
            lookup: VMStoredObject(lookup)
          )
        case .directColorants(let space, let names):
          self = .directColorants(space: space, names: names)
        case .alternative(let space, let names, let transform, let colorSpace):
          self = .alternative(
            space: space,
            names: names,
            transform: VMStoredObject(transform),
            colorSpace: Self(colorSpace)
          )
        case .pattern(let underlying):
          self = .pattern(underlying: underlying.map(Self.init))
        }
      }

      var value: PostScriptColorSelection.Route {
        switch self {
        case .colorSpace(let colorSpace):
          .colorSpace(colorSpace.colorSpace)
        case .indexed(let base, let maximumIndex, let lookup):
          .indexed(base: base.value, maximumIndex: maximumIndex, lookup: lookup.object)
        case .directColorants(let space, let names):
          .directColorants(space: space, names: names)
        case .alternative(let space, let names, let transform, let colorSpace):
          .alternative(
            space: space,
            names: names,
            transform: transform.object,
            colorSpace: colorSpace.value
          )
        case .pattern(let underlying):
          .pattern(underlying: underlying?.value)
        }
      }

      var storedObjects: [VMStoredObject] {
        switch self {
        case .colorSpace(let colorSpace): colorSpace.storedObjects
        case .indexed(let base, _, let lookup): base.storedObjects + [lookup]
        case .directColorants: []
        case .alternative(_, _, let transform, let colorSpace):
          colorSpace.storedObjects + [transform]
        case .pattern(let underlying): underlying?.storedObjects ?? []
        }
      }
    }

    let source: VMStoredColorSpace
    let route: Route

    init(_ selection: PostScriptColorSelection) {
      self.source = VMStoredColorSpace(selection.source)
      self.route = Route(selection.route)
    }

    var value: PostScriptColorSelection {
      PostScriptColorSelection(source: source.colorSpace, route: route.value)
    }

    var storedObjects: [VMStoredObject] { source.storedObjects + route.storedObjects }

    func identifyEdges(from allocation: VMAllocation) {
      storedObjects.forEach { $0.identifyEdgeSource(allocation) }
    }

    func refreshEdges() {
      storedObjects.forEach { $0.refreshEdge() }
    }
  }
}
