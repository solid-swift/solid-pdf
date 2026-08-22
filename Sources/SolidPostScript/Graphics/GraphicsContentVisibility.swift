/// Whether a semantic graphics operation participates in visible output.
public enum GraphicsContentVisibility: Sendable, Hashable {
  /// The operation is visible in the selected document configuration.
  case visible
  /// The operation is suppressed by the identified optional-content scopes.
  case hidden([GraphicsResourceIdentifier])

  /// Whether a visual target should realize the operation.
  public var isVisible: Bool {
    if case .visible = self { return true }
    return false
  }
}
