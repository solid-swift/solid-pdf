/// Controls exact raster fallback for PDF effects that cannot be represented natively.
public enum PDFFallbackPolicy: Sendable, Hashable {
  /// Rasterize the smallest equivalent region, escalating to a page when required.
  case exact
  /// Reject any effect that cannot remain vector or native sampled content.
  case vectorOnly
}
