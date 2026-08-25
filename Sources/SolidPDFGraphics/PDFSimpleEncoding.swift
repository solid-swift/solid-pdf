import Foundation
import SolidFont
import SolidPDF
import SolidPostScript

struct PDFSimpleEncoding: Sendable, Hashable {
  struct Entry: Sendable, Hashable {
    let glyphName: String
    let unicodeScalars: [Unicode.Scalar]?
  }

  private var entries: [Entry]

  init(baseName: String = "StandardEncoding") throws {
    entries = try (0...255).map { code in
      let byte = UInt8(code)
      switch baseName {
      case "StandardEncoding":
        let name = StandardEncodings.standardName(for: byte)
        return Entry(glyphName: name, unicodeScalars: AdobeGlyphList.unicodeScalars(for: name))
      case "WinAnsiEncoding":
        return Self.entry(byte: byte, encoding: .windowsCP1252)
      case "MacRomanEncoding":
        return Self.entry(byte: byte, encoding: .macOSRoman)
      case "MacExpertEncoding":
        return Entry(glyphName: Self.macExpertNames[code] ?? ".notdef", unicodeScalars: nil)
      case "Symbol":
        return Entry(glyphName: Self.symbolNames[code] ?? ".notdef", unicodeScalars: nil)
      case "ZapfDingbats":
        return Entry(glyphName: code >= 32 ? "a\(code - 31)" : ".notdef", unicodeScalars: nil)
      default: throw PDFObjectAccess.TypeMismatch.name
      }
    }
  }

  subscript(code: UInt8) -> Entry { entries[Int(code)] }

  mutating func applyDifferences(_ values: [PDFObject]) throws {
    var code: Int?
    for value in values {
      switch value {
      case .number:
        let start = try PDFObjectAccess.integer(value)
        guard (0...255).contains(start) else { throw PDFObjectAccess.TypeMismatch.integer }
        code = start
      case .name(let name):
        guard let current = code, current <= 255 else { throw PDFObjectAccess.TypeMismatch.array }
        let glyphName = name.pdfGraphicsString
        entries[current] = Entry(
          glyphName: glyphName,
          unicodeScalars: AdobeGlyphList.unicodeScalars(for: glyphName)
        )
        code = current + 1
      default: throw PDFObjectAccess.TypeMismatch.array
      }
    }
  }

  private static func entry(byte: UInt8, encoding: String.Encoding) -> Entry {
    guard let string = String(data: Data([byte]), encoding: encoding),
      let scalar = string.unicodeScalars.first, string.unicodeScalars.count == 1
    else { return Entry(glyphName: ".notdef", unicodeScalars: nil) }
    let name = glyphName(for: scalar)
    return Entry(glyphName: name, unicodeScalars: [scalar])
  }

  private static func glyphName(for scalar: Unicode.Scalar) -> String {
    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
      if scalar.value < 0x80 { return String(scalar) }
    }
    if let name = asciiNames[scalar.value] { return name }
    return String(format: scalar.value <= 0xFFFF ? "uni%04X" : "u%05X", scalar.value)
  }

  private static let asciiNames: [UInt32: String] = [
    0x20: "space", 0x21: "exclam", 0x22: "quotedbl", 0x23: "numbersign",
    0x24: "dollar", 0x25: "percent", 0x26: "ampersand", 0x27: "quotesingle",
    0x28: "parenleft", 0x29: "parenright", 0x2A: "asterisk", 0x2B: "plus",
    0x2C: "comma", 0x2D: "hyphen", 0x2E: "period", 0x2F: "slash",
    0x3A: "colon", 0x3B: "semicolon", 0x3C: "less", 0x3D: "equal",
    0x3E: "greater", 0x3F: "question", 0x40: "at", 0x5B: "bracketleft",
    0x5C: "backslash", 0x5D: "bracketright", 0x5E: "asciicircum",
    0x5F: "underscore", 0x60: "grave", 0x7B: "braceleft", 0x7C: "bar",
    0x7D: "braceright", 0x7E: "asciitilde",
  ]

  private static let macExpertNames: [Int: String] = [
    32: "space", 33: "exclamsmall", 34: "Hungarumlautsmall", 35: "centoldstyle",
    36: "dollaroldstyle", 37: "dollarsuperior", 38: "ampersandsmall", 39: "Acutesmall",
    48: "zerooldstyle", 49: "oneoldstyle", 50: "twooldstyle", 51: "threeoldstyle",
    52: "fouroldstyle", 53: "fiveoldstyle", 54: "sixoldstyle", 55: "sevenoldstyle",
    56: "eightoldstyle", 57: "nineoldstyle", 87: "ff", 88: "fi", 89: "fl",
    90: "ffi", 91: "ffl",
  ]

  private static let symbolNames: [Int: String] = [
    32: "space", 33: "exclam", 34: "universal", 35: "numbersign", 36: "existential",
    37: "percent", 38: "ampersand", 39: "suchthat", 40: "parenleft", 41: "parenright",
    42: "asteriskmath", 43: "plus", 45: "minus", 47: "slash", 61: "equal",
    65: "Alpha", 66: "Beta", 67: "Chi", 68: "Delta", 69: "Epsilon", 70: "Phi",
    71: "Gamma", 72: "Eta", 73: "Iota", 74: "theta1", 75: "Kappa", 76: "Lambda",
    77: "Mu", 78: "Nu", 79: "Omicron", 80: "Pi", 81: "Theta", 82: "Rho",
    83: "Sigma", 84: "Tau", 85: "Upsilon", 86: "sigma1", 87: "Omega",
    88: "Xi", 89: "Psi", 90: "Zeta",
  ]
}
