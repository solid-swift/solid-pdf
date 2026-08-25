/// The version of the portable semantic graphics contract.
public struct GraphicsSemanticContractVersion: RawRepresentable, Sendable, Hashable, Comparable {
  /// The integer contract version.
  public let rawValue: Int

  /// Creates a semantic contract version.
  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// The first frozen document-processing contract.
  public static let v1 = Self(rawValue: 1)

  /// The PDF text styling and extraction contract.
  public static let v2 = Self(rawValue: 2)

  /// The marked-content, optional-content, and logical-structure contract.
  public static let v3 = Self(rawValue: 3)

  /// The PDF transparency, compositing, and atomic-paint contract.
  public static let v4 = Self(rawValue: 4)

  /// The contract emitted by this version of SolidPostScript.
  public static let current = v4

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
