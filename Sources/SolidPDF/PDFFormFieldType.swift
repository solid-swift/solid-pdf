/// A standard AcroForm field type.
public enum PDFFormFieldType: Sendable, Hashable {
  case button
  case text
  case choice
  case signature
}

/// Flags controlling AcroForm field behavior.
public struct PDFFormFieldFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let readOnly = Self(rawValue: 1 << 0)
  public static let required = Self(rawValue: 1 << 1)
  public static let noExport = Self(rawValue: 1 << 2)
  public static let multiline = Self(rawValue: 1 << 12)
  public static let password = Self(rawValue: 1 << 13)
  public static let noToggleToOff = Self(rawValue: 1 << 14)
  public static let radio = Self(rawValue: 1 << 15)
  public static let pushButton = Self(rawValue: 1 << 16)
  public static let combo = Self(rawValue: 1 << 17)
  public static let edit = Self(rawValue: 1 << 18)
  public static let sort = Self(rawValue: 1 << 19)
  public static let fileSelect = Self(rawValue: 1 << 20)
  public static let multiSelect = Self(rawValue: 1 << 21)
  public static let doNotSpellCheck = Self(rawValue: 1 << 22)
  public static let doNotScroll = Self(rawValue: 1 << 23)
  public static let comb = Self(rawValue: 1 << 24)
  public static let richText = Self(rawValue: 1 << 25)
  public static let radiosInUnison = Self(rawValue: 1 << 25)
  public static let commitOnSelectionChange = Self(rawValue: 1 << 26)
}
