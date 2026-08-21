import Foundation

enum GraphicsMediaMatcher {
  static func select(
    request: GraphicsMediaRequest,
    catalog: GraphicsMediaCatalog,
    rollFed: Bool
  ) -> GraphicsMediaSource? {
    let candidates = catalog.sources.values.filter {
      matches(request: request, source: $0, rollFed: rollFed)
    }
    guard !candidates.isEmpty else { return nil }
    let priority = Dictionary(uniqueKeysWithValues: catalog.priority.enumerated().map { ($1, $0) })
    return candidates.min {
      let lhs = priority[$0.position] ?? Int.max
      let rhs = priority[$1.position] ?? Int.max
      return lhs == rhs ? $0.position < $1.position : lhs < rhs
    }
  }

  static func unsatisfiedParameters(
    request: GraphicsMediaRequest,
    catalog: GraphicsMediaCatalog,
    rollFed: Bool
  ) -> Set<String> {
    var result: Set<String> = []
    let candidates = catalog.sources.values.filter {
      $0.attributes != nil && $0.isManual == request.manualFeed
        && (request.position == nil || $0.position == request.position)
    }
    guard !candidates.isEmpty else {
      if request.manualFeed { result.insert("ManualFeed") }
      if request.position != nil { result.insert("MediaPosition") }
      return result
    }
    let requested = request.attributes
    if let value = requested.pageSize,
      !candidates.contains(where: { source in
        source.attributes?.pageSize.map { pageSizeMatches(value, $0, rollFed: rollFed) } ?? false
      })
    { result.insert("PageSize") }
    if let value = requested.color,
      !candidates.contains(where: { $0.attributes?.color == value })
    { result.insert("MediaColor") }
    if let value = requested.weight,
      !candidates.contains(where: { $0.attributes?.weight == value })
    { result.insert("MediaWeight") }
    if let value = requested.type,
      !candidates.contains(where: { $0.attributes?.type == value })
    { result.insert("MediaType") }
    if let value = requested.mediaClass,
      !candidates.contains(where: { $0.attributes?.mediaClass == value })
    { result.insert("MediaClass") }
    if let value = requested.insertsSheet,
      !candidates.contains(where: { $0.attributes?.insertsSheet == value })
    { result.insert("InsertSheet") }
    return result.isEmpty ? ["PageSize"] : result
  }

  static func alternative(
    request: GraphicsMediaRequest,
    catalog: GraphicsMediaCatalog,
    nextLarger: Bool
  ) -> GraphicsMediaSource? {
    guard let requestedSize = request.attributes.pageSize else { return nil }
    let requestWithoutSize = GraphicsMediaRequest(
      attributes: GraphicsMediaAttributes(
        color: request.attributes.color,
        weight: request.attributes.weight,
        type: request.attributes.type,
        mediaClass: request.attributes.mediaClass,
        insertsSheet: request.attributes.insertsSheet
      ),
      leadingEdge: request.leadingEdge,
      manualFeed: request.manualFeed,
      position: request.position,
      traySwitch: request.traySwitch,
      isDeferred: false
    )
    let candidates = catalog.sources.values.filter {
      matches(request: requestWithoutSize, source: $0, rollFed: false)
        && $0.attributes?.pageSize != nil
    }
    guard !candidates.isEmpty else { return nil }
    let requestedArea = requestedSize.width * requestedSize.height
    let priority = Dictionary(uniqueKeysWithValues: catalog.priority.enumerated().map { ($1, $0) })
    func ordered(_ lhs: GraphicsMediaSource, _ rhs: GraphicsMediaSource) -> Bool {
      guard let lhsSize = lhs.attributes?.pageSize, let rhsSize = rhs.attributes?.pageSize else {
        return lhs.position < rhs.position
      }
      let lhsArea = lhsSize.width * lhsSize.height
      let rhsArea = rhsSize.width * rhsSize.height
      let lhsDistance = abs(lhsArea - requestedArea)
      let rhsDistance = abs(rhsArea - requestedArea)
      if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
      let lhsPriority = priority[lhs.position] ?? Int.max
      let rhsPriority = priority[rhs.position] ?? Int.max
      return lhsPriority == rhsPriority ? lhs.position < rhs.position : lhsPriority < rhsPriority
    }
    if nextLarger {
      let larger = candidates.filter { source in
        guard let size = source.attributes?.pageSize else { return false }
        return (size.width >= requestedSize.width && size.height >= requestedSize.height)
          || (size.height >= requestedSize.width && size.width >= requestedSize.height)
      }
      if let selected = larger.min(by: ordered) { return selected }
    }
    return candidates.min(by: ordered)
  }

  private static func matches(
    request: GraphicsMediaRequest,
    source: GraphicsMediaSource,
    rollFed: Bool
  ) -> Bool {
    guard let available = source.attributes,
      source.isManual == request.manualFeed,
      request.position == nil || request.position == source.position
    else { return false }
    let requested = request.attributes
    if let value = requested.pageSize {
      guard let candidate = available.pageSize,
        pageSizeMatches(value, candidate, rollFed: rollFed)
      else { return false }
    }
    if let value = requested.color, available.color != value { return false }
    if let value = requested.weight, available.weight != value { return false }
    if let value = requested.type, available.type != value { return false }
    if let value = requested.mediaClass, available.mediaClass != value { return false }
    if let value = requested.insertsSheet, available.insertsSheet != value { return false }
    guard source.matchesAllAttributes else { return true }
    return (available.pageSize == nil || requested.pageSize != nil)
      && (available.color == nil || requested.color != nil)
      && (available.weight == nil || requested.weight != nil)
      && (available.type == nil || requested.type != nil)
      && (available.mediaClass == nil || requested.mediaClass != nil)
      && (available.insertsSheet == nil || requested.insertsSheet != nil)
  }

  private static func pageSizeMatches(
    _ requested: GraphicsSize,
    _ available: GraphicsSize,
    rollFed: Bool
  ) -> Bool {
    dimensionsMatch(requested, available, rollFed: rollFed)
      || dimensionsMatch(
        requested,
        GraphicsSize(width: available.height, height: available.width),
        rollFed: rollFed
      )
  }

  private static func dimensionsMatch(
    _ requested: GraphicsSize,
    _ available: GraphicsSize,
    rollFed: Bool
  ) -> Bool {
    if rollFed {
      return requested.width <= available.width + 5 && requested.height <= available.height + 5
    }
    return abs(requested.width - available.width) <= 5
      && abs(requested.height - available.height) <= 5
  }
}
