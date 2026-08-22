import Foundation

package extension SFNTCollection {
  func glyph(
    data: Data,
    faceIndex: Int,
    glyphIndex: UInt32,
    selector: FontGlyphSelector,
    limits: FontParsingLimits = .default
  ) throws -> FontGlyph {
    guard faces.indices.contains(faceIndex) else { throw FontError.range }
    let source = try TrueTypeSource(data: data, face: faces[faceIndex], faceIndex: faceIndex, limits: limits)
    return try source.glyph(glyphIndex, selector: selector, maximumDepth: limits.maximumSubroutineDepth)
  }

  func glyphIndex(
    data: Data,
    faceIndex: Int,
    unicodeScalar: Unicode.Scalar,
    limits: FontParsingLimits = .default
  ) throws -> UInt32? {
    guard faces.indices.contains(faceIndex) else { throw FontError.range }
    let source = try TrueTypeSource(data: data, face: faces[faceIndex], faceIndex: faceIndex, limits: limits)
    return source.glyphIndex(for: unicodeScalar)
  }
}

package extension FontOutline.Element {
  func transformed(a: Double, b: Double, c: Double, d: Double, dx: Double, dy: Double) -> Self {
    func point(_ value: FontPoint) -> FontPoint {
      FontPoint(
        x: a * value.x + c * value.y + dx,
        y: b * value.x + d * value.y + dy
      )
    }
    return switch self {
    case .move(let value): .move(point(value))
    case .line(let value): .line(point(value))
    case .quadratic(let control, let end): .quadratic(control: point(control), end: point(end))
    case .cubic(let control1, let control2, let end):
      .cubic(control1: point(control1), control2: point(control2), end: point(end))
    case .close: .close
    }
  }
}
