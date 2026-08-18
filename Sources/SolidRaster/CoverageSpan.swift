import Foundation

struct CoverageSpan: Sendable, Hashable {
  var x: Int
  var y: Int
  var length: Int
  var coverage: UInt8
}
