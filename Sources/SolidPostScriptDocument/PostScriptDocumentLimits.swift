/// Resource limits used while scanning DSC and EPS containers.
public struct PostScriptDocumentLimits: Sendable, Hashable {
  public var maximumInputBytes: Int
  public var maximumLineBytes: Int
  public var maximumPages: Int
  public var maximumNestingDepth: Int

  /// Creates document parsing limits.
  public init(
    maximumInputBytes: Int = 512 * 1_024 * 1_024,
    maximumLineBytes: Int = 1 * 1_024 * 1_024,
    maximumPages: Int = 1_000_000,
    maximumNestingDepth: Int = 1_024
  ) {
    self.maximumInputBytes = maximumInputBytes
    self.maximumLineBytes = maximumLineBytes
    self.maximumPages = maximumPages
    self.maximumNestingDepth = maximumNestingDepth
  }
}
