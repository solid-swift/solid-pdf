import Foundation

/// The page-object class used by raster trap analysis.
package enum RasterTrappingMarkKind: UInt8, Sendable, Hashable {
  case vector = 0
  case text = 1
  case shading = 2
  case image = 3
}
