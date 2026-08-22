/// Resource limits for one PDF graphics interpretation.
public struct PDFGraphicsLimits: Sendable, Hashable {
  /// Maximum operators executed on one page.
  public let maximumOperatorsPerPage: Int
  /// Maximum saved PDF graphics-state entries.
  public let maximumGraphicsStateDepth: Int
  /// Maximum nested resource, form, and pattern scopes.
  public let maximumResourceDepth: Int
  /// Maximum decoded pixels in one image.
  public let maximumImagePixels: Int
  /// Maximum interpretation scratch retained by one render.
  public let maximumScratchBytes: Int

  /// Creates interpretation limits.
  public init(
    maximumOperatorsPerPage: Int = 10_000_000,
    maximumGraphicsStateDepth: Int = 256,
    maximumResourceDepth: Int = 64,
    maximumImagePixels: Int = 128_000_000,
    maximumScratchBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.maximumOperatorsPerPage = maximumOperatorsPerPage
    self.maximumGraphicsStateDepth = maximumGraphicsStateDepth
    self.maximumResourceDepth = maximumResourceDepth
    self.maximumImagePixels = maximumImagePixels
    self.maximumScratchBytes = maximumScratchBytes
  }
}
