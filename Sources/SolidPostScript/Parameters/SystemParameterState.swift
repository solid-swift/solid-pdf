import Foundation

struct SystemParameterState: Sendable {
  enum Access {
    case readOnly
    case readWrite(UserParameterState.Definition)
    case writeOnly(UserParameterState.Definition)
  }

  static let definitions: [String: Access] = [
    "ByteOrder": .readOnly,
    "BuildTime": .readOnly,
    "CurDisplayList": .readOnly,
    "CurFontCache": .readOnly,
    "CurFormCache": .readOnly,
    "CurOutlineCache": .readOnly,
    "CurPatternCache": .readOnly,
    "CurScreenStorage": .readOnly,
    "CurSourceList": .readOnly,
    "CurStoredScreenCache": .readOnly,
    "CurUPathCache": .readOnly,
    "FactoryDefaults": .readWrite(.boolean),
    "FontResourceDir": .readWrite(.string(maximumLength: nil)),
    "GenericResourceDir": .readWrite(.string(maximumLength: nil)),
    "GenericResourcePathSep": .readWrite(.string(maximumLength: nil)),
    "LicenseID": .readOnly,
    "MaxDisplayAndSourceList": .readWrite(.integer {
      min(max($0, 0), Int32(GraphicsStorageLedger.maximumCombinedBytes))
    }),
    "MaxDisplayList": .readWrite(.integer {
      min(max($0, 0), Int32(GraphicsStorageLedger.maximumDisplayBytes))
    }),
    "MaxFontCache": .readWrite(.integer { min(max($0, 0), Int32(FontGlyphCache.maximumBytes)) }),
    "MaxFormCache": .readWrite(.integer { min(max($0, 0), Int32(FormCache.maximumBytes)) }),
    "MaxImageBuffer": .readWrite(.integer {
      min(max($0, 0), Int32(GraphicsStorageLedger.maximumImageBufferBytes))
    }),
    "MaxOutlineCache": .readWrite(.integer {
      min(max($0, 0), Int32(FontOutlineCache.maximumBytes))
    }),
    "MaxPatternCache": .readWrite(.integer { min(max($0, 0), Int32(PatternCache.maximumBytes)) }),
    "MaxScreenStorage": .readWrite(.integer {
      min(max($0, 0), Int32(ScreenManager.maximumActiveBytes))
    }),
    "MaxSourceList": .readWrite(.integer {
      min(max($0, 0), Int32(GraphicsStorageLedger.maximumSourceBytes))
    }),
    "MaxStoredScreenCache": .readWrite(.integer {
      min(max($0, 0), Int32(ScreenManager.maximumCachedBytes))
    }),
    "MaxUPathCache": .readWrite(.integer { min(max($0, 0), Int32(UserPathCache.maximumBytes)) }),
    "PageCount": .readOnly,
    "PrinterName": .readWrite(.string(maximumLength: nil)),
    "RealFormat": .readOnly,
    "Revision": .readOnly,
    "StartJobPassword": .writeOnly(.string(maximumLength: nil)),
    "StartupMode": .readWrite(.nonnegativeInteger),
    "SystemParamsPassword": .writeOnly(.string(maximumLength: nil)),
  ]

  var values: [String: ParameterValue]
  var userDefaults: UserParameterState
  var systemPassword = Data()
  var startJobPassword = Data()

  init() {
    var endianProbe: UInt16 = 1
    let littleEndian = withUnsafeBytes(of: &endianProbe) { $0[0] == 1 }
    self.values = [
      "ByteOrder": .boolean(littleEndian),
      "BuildTime": .integer(0),
      "CurDisplayList": .integer(0),
      "CurFontCache": .integer(0),
      "CurFormCache": .integer(0),
      "CurOutlineCache": .integer(0),
      "CurPatternCache": .integer(0),
      "CurScreenStorage": .integer(0),
      "CurSourceList": .integer(0),
      "CurStoredScreenCache": .integer(0),
      "CurUPathCache": .integer(0),
      "FactoryDefaults": .boolean(false),
      "FontResourceDir": .string(Data("%null".utf8)),
      "GenericResourceDir": .string(Data("%null".utf8)),
      "GenericResourcePathSep": .string(Data("/".utf8)),
      "LicenseID": .string(Data()),
      "MaxDisplayAndSourceList": .integer(Int32(GraphicsStorageLedger.maximumCombinedBytes)),
      "MaxDisplayList": .integer(Int32(GraphicsStorageLedger.maximumDisplayBytes)),
      "MaxFontCache": .integer(Int32(FontGlyphCache.maximumBytes)),
      "MaxFormCache": .integer(Int32(FormCache.maximumBytes)),
      "MaxImageBuffer": .integer(Int32(GraphicsStorageLedger.maximumImageBufferBytes)),
      "MaxOutlineCache": .integer(Int32(FontOutlineCache.maximumBytes)),
      "MaxPatternCache": .integer(Int32(PatternCache.maximumBytes)),
      "MaxScreenStorage": .integer(Int32(ScreenManager.maximumActiveBytes)),
      "MaxSourceList": .integer(Int32(GraphicsStorageLedger.maximumSourceBytes)),
      "MaxStoredScreenCache": .integer(Int32(ScreenManager.maximumCachedBytes)),
      "MaxUPathCache": .integer(Int32(UserPathCache.maximumBytes)),
      "PageCount": .integer(0),
      "PrinterName": .string(Data("SolidPostScript".utf8)),
      "RealFormat": .string(Data("IEEE".utf8)),
      "Revision": .integer(0),
      "StartupMode": .integer(0),
    ]
    self.userDefaults = UserParameterState()
  }

  var currentValues: [String: ParameterValue] {
    values.merging(userDefaults.values) { value, _ in value }
  }
}
