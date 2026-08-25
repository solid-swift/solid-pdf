import Foundation

package struct PDFVariableTextAppearanceStyle: Sendable, Hashable {
  package let fontName: PDFName
  package let fontSize: Double
  package let colorOperator: String
  package let colorComponents: [Double]
  package let prefix: Data
}

package enum PDFVariableTextAppearanceSupport {
  package static func style(from appearance: PDFString) -> PDFVariableTextAppearanceStyle? {
    guard let source = String(data: appearance.bytes, encoding: .utf8) else { return nil }
    let tokens = source.split(whereSeparator: \Character.isWhitespace).map(String.init)
    guard let index = tokens.firstIndex(of: "Tf"), index >= 2,
      tokens[index - 2].hasPrefix("/"),
      let size = Double(tokens[index - 1]),
      size >= 0
    else { return nil }
    let color: (String, [Double])
    if let colorIndex = tokens.lastIndex(of: "g"), colorIndex >= 1,
      let gray = Double(tokens[colorIndex - 1])
    {
      color = ("g", [gray])
    } else if let colorIndex = tokens.lastIndex(of: "rg"), colorIndex >= 3 {
      let values = tokens[(colorIndex - 3)..<colorIndex].compactMap(Double.init)
      color = values.count == 3 ? ("rg", values) : ("g", [0])
    } else if let colorIndex = tokens.lastIndex(of: "k"), colorIndex >= 4 {
      let values = tokens[(colorIndex - 4)..<colorIndex].compactMap(Double.init)
      color = values.count == 4 ? ("k", values) : ("g", [0])
    } else {
      color = ("g", [0])
    }
    return PDFVariableTextAppearanceStyle(
      fontName: PDFName(String(tokens[index - 2].dropFirst())),
      fontSize: size,
      colorOperator: color.0,
      colorComponents: color.1,
      prefix: appearance.bytes
    )
  }

  package static func decodedText(_ value: PDFString) throws -> String {
    try PDFTextStringDecoder.decode(value, allowsUTF8: true)
  }

  static func encodedGlyphBytes(_ text: String, encoding: PDFName?) -> Data? {
    let stringEncoding: String.Encoding
    switch encoding {
    case "WinAnsiEncoding": stringEncoding = .windowsCP1252
    case "MacRomanEncoding": stringEncoding = .macOSRoman
    case nil, "StandardEncoding":
      guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E || $0.value == 0x0A }) else {
        return nil
      }
      return Data(text.utf8)
    default:
      return nil
    }
    return text.data(using: stringEncoding, allowLossyConversion: false)
  }
}
