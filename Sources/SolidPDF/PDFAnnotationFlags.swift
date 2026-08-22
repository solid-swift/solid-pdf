/// Flags controlling annotation visibility, printing, interaction, and placement.
public struct PDFAnnotationFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let invisible = Self(rawValue: 1 << 0)
  public static let hidden = Self(rawValue: 1 << 1)
  public static let print = Self(rawValue: 1 << 2)
  public static let noZoom = Self(rawValue: 1 << 3)
  public static let noRotate = Self(rawValue: 1 << 4)
  public static let noView = Self(rawValue: 1 << 5)
  public static let readOnly = Self(rawValue: 1 << 6)
  public static let locked = Self(rawValue: 1 << 7)
  public static let toggleNoView = Self(rawValue: 1 << 8)
  public static let lockedContents = Self(rawValue: 1 << 9)
}
