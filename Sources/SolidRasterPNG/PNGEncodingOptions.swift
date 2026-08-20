/// Portable PNG encoding options.
public struct PNGEncodingOptions: Sendable, Hashable {
  public enum FilterStrategy: Sendable, Hashable {
    case adaptive
    case fixed(PNGFilter)
  }

  public var colorFormat: PNGColorFormat
  public var filterStrategy: FilterStrategy
  public var compressionLevel: Int
  public var resolutionDPI: Double?
  public var background: PNGBackground

  /// Creates encoding options.
  public init(
    colorFormat: PNGColorFormat = .rgb,
    filterStrategy: FilterStrategy = .adaptive,
    compressionLevel: Int = 6,
    resolutionDPI: Double? = nil,
    background: PNGBackground = .white
  ) {
    self.colorFormat = colorFormat
    self.filterStrategy = filterStrategy
    self.compressionLevel = compressionLevel
    self.resolutionDPI = resolutionDPI
    self.background = background
  }
}
