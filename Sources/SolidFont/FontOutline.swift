import Foundation

/// A portable glyph outline.
public struct FontOutline: Sendable, Hashable {
  /// One element in a glyph outline.
  public enum Element: Sendable, Hashable {
    /// Starts a contour.
    case move(FontPoint)
    /// Adds a straight segment.
    case line(FontPoint)
    /// Adds a quadratic Bezier segment.
    case quadratic(control: FontPoint, end: FontPoint)
    /// Adds a cubic Bezier segment.
    case cubic(control1: FontPoint, control2: FontPoint, end: FontPoint)
    /// Closes the current contour.
    case close
  }

  /// The ordered outline elements.
  public let elements: [Element]

  /// Creates an outline.
  public init(elements: [Element]) {
    self.elements = elements
  }
}
