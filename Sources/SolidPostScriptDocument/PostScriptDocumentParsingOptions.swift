/// Controls DSC conformance checking.
public struct PostScriptDocumentParsingOptions: Sendable, Hashable {
  public var strict: Bool
  public var assumedKind: PostScriptDocumentKind?
  public var limits: PostScriptDocumentLimits

  /// Creates parsing options.
  public init(
    strict: Bool = true,
    assumedKind: PostScriptDocumentKind? = nil,
    limits: PostScriptDocumentLimits = .init()
  ) {
    self.strict = strict
    self.assumedKind = assumedKind
    self.limits = limits
  }
}
