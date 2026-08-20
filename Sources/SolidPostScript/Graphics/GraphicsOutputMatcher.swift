import Foundation

enum GraphicsOutputMatcher {
  static func select(type: Data?, catalog: GraphicsOutputCatalog) -> GraphicsOutputDestination? {
    let candidates = catalog.destinations.values.filter { destination in
      guard let type else { return !destination.matchesAllAttributes }
      return destination.type == type
    }
    let priority = Dictionary(uniqueKeysWithValues: catalog.priority.enumerated().map { ($1, $0) })
    return candidates.min {
      let lhs = priority[$0.position] ?? Int.max
      let rhs = priority[$1.position] ?? Int.max
      return lhs == rhs ? $0.position < $1.position : lhs < rhs
    }
  }
}
