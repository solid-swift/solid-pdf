import Foundation

/// A deterministic failure raised by portable raster operations.
public enum RasterError: Error, Sendable, Hashable {
  case invalidGeometry
  case invalidImage
  case coordinateOverflow
  case limitExceeded
  case finishedCanvas
}
