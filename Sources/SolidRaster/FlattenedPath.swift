import Foundation

struct FlattenedPath {
  struct Subpath {
    var points: ContiguousArray<RasterPoint>
    var isClosed: Bool
  }

  var subpaths: ContiguousArray<Subpath>
}
