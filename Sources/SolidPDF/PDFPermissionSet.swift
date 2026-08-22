/// Effective permissions declared by a PDF standard security handler.
public struct PDFPermissionSet: OptionSet, Sendable, Hashable {
  /// The raw permission bit set.
  public let rawValue: UInt32

  /// Creates a permission set from its raw value.
  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// Printing is permitted.
  public static let print = Self(rawValue: 1 << 2)
  /// Document modification is permitted.
  public static let modify = Self(rawValue: 1 << 3)
  /// Text and graphics extraction is permitted.
  public static let extract = Self(rawValue: 1 << 4)
  /// Annotation and form modification is permitted.
  public static let annotate = Self(rawValue: 1 << 5)
  /// Form filling is permitted.
  public static let fillForms = Self(rawValue: 1 << 8)
  /// Accessibility extraction is permitted.
  public static let accessibility = Self(rawValue: 1 << 9)
  /// Document assembly is permitted.
  public static let assemble = Self(rawValue: 1 << 10)
  /// High-quality printing is permitted.
  public static let highQualityPrint = Self(rawValue: 1 << 11)

  /// Every semantic operation is permitted.
  public static let all: Self = [
    .print, .modify, .extract, .annotate, .fillForms, .accessibility, .assemble,
    .highQualityPrint,
  ]
}
