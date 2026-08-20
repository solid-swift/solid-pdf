/// A PNG scanline prediction filter.
public enum PNGFilter: Sendable, Hashable, CaseIterable {
  case none
  case sub
  case up
  case average
  case paeth
}
