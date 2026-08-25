/// The registry, ordering, and supplement that identify a CID character collection.
public struct FontCIDSystemInfo: Sendable, Hashable {
  /// The organization that defines the collection.
  public let registry: String
  /// The collection name within the registry.
  public let ordering: String
  /// The collection supplement number.
  public let supplement: Int

  /// Creates CID collection metadata.
  public init(registry: String, ordering: String, supplement: Int) throws {
    guard !registry.isEmpty, !ordering.isEmpty, supplement >= 0 else { throw FontError.invalidData }
    self.registry = registry
    self.ordering = ordering
    self.supplement = supplement
  }
}
