import Foundation

enum StandardEncodings {
  static func standardName(for code: UInt8) -> String {
    standardNames[Int(code)] ?? ".notdef"
  }

  static func standard(vm: VM = .global) throws -> Object {
    try encoding(overrides: standardNames, vm: vm)
  }

  static func isoLatin1(vm: VM = .global) throws -> Object {
    var names = asciiNames
    let latin1: [Int: String] = [
      160: "space", 161: "exclamdown", 162: "cent", 163: "sterling", 164: "currency",
      165: "yen", 166: "brokenbar", 167: "section", 168: "dieresis", 169: "copyright",
      170: "ordfeminine", 171: "guillemotleft", 172: "logicalnot", 173: "hyphen",
      174: "registered", 175: "macron", 176: "degree", 177: "plusminus", 178: "twosuperior",
      179: "threesuperior", 180: "acute", 181: "mu", 182: "paragraph", 183: "periodcentered",
      184: "cedilla", 185: "onesuperior", 186: "ordmasculine", 187: "guillemotright",
      188: "onequarter", 189: "onehalf", 190: "threequarters", 191: "questiondown",
      192: "Agrave", 193: "Aacute", 194: "Acircumflex", 195: "Atilde", 196: "Adieresis",
      197: "Aring", 198: "AE", 199: "Ccedilla", 200: "Egrave", 201: "Eacute",
      202: "Ecircumflex", 203: "Edieresis", 204: "Igrave", 205: "Iacute", 206: "Icircumflex",
      207: "Idieresis", 208: "Eth", 209: "Ntilde", 210: "Ograve", 211: "Oacute",
      212: "Ocircumflex", 213: "Otilde", 214: "Odieresis", 215: "multiply", 216: "Oslash",
      217: "Ugrave", 218: "Uacute", 219: "Ucircumflex", 220: "Udieresis", 221: "Yacute",
      222: "Thorn", 223: "germandbls", 224: "agrave", 225: "aacute", 226: "acircumflex",
      227: "atilde", 228: "adieresis", 229: "aring", 230: "ae", 231: "ccedilla",
      232: "egrave", 233: "eacute", 234: "ecircumflex", 235: "edieresis", 236: "igrave",
      237: "iacute", 238: "icircumflex", 239: "idieresis", 240: "eth", 241: "ntilde",
      242: "ograve", 243: "oacute", 244: "ocircumflex", 245: "otilde", 246: "odieresis",
      247: "divide", 248: "oslash", 249: "ugrave", 250: "uacute", 251: "ucircumflex",
      252: "udieresis", 253: "yacute", 254: "thorn", 255: "ydieresis",
    ]
    names.merge(latin1) { _, replacement in replacement }
    return try encoding(overrides: names, vm: vm)
  }

  private static func encoding(overrides: [Int: String], vm: VM) throws -> Object {
    var values = Array(repeating: Object.literalName(".notdef"), count: 256)
    for (index, name) in overrides { values[index] = .literalName(name) }
    return try .array(values, access: .readOnly, vm: vm, kind: .literal)
  }

  private static let asciiNames: [Int: String] = {
    let punctuation: [Int: String] = [
      32: "space", 33: "exclam", 34: "quotedbl", 35: "numbersign", 36: "dollar",
      37: "percent", 38: "ampersand", 39: "quoteright", 40: "parenleft", 41: "parenright",
      42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen", 46: "period", 47: "slash",
      48: "zero", 49: "one", 50: "two", 51: "three", 52: "four", 53: "five",
      54: "six", 55: "seven", 56: "eight", 57: "nine", 58: "colon", 59: "semicolon",
      60: "less", 61: "equal", 62: "greater", 63: "question", 64: "at",
      91: "bracketleft", 92: "backslash", 93: "bracketright", 94: "asciicircum",
      95: "underscore", 96: "quoteleft", 123: "braceleft", 124: "bar", 125: "braceright",
      126: "asciitilde",
    ]
    var result = punctuation
    for code in 65...90 { result[code] = String(UnicodeScalar(code)!) }
    for code in 97...122 { result[code] = String(UnicodeScalar(code)!) }
    return result
  }()

  private static let standardNames: [Int: String] = {
    var result = asciiNames
    let high: [Int: String] = [
      161: "exclamdown", 162: "cent", 163: "sterling", 164: "fraction", 165: "yen",
      166: "florin", 167: "section", 168: "currency", 169: "quotesingle", 170: "quotedblleft",
      171: "guillemotleft", 172: "guilsinglleft", 173: "guilsinglright", 174: "fi", 175: "fl",
      177: "endash", 178: "dagger", 179: "daggerdbl", 180: "periodcentered", 182: "paragraph",
      183: "bullet", 184: "quotesinglbase", 185: "quotedblbase", 186: "quotedblright",
      187: "guillemotright", 188: "ellipsis", 189: "perthousand", 191: "questiondown",
      193: "grave", 194: "acute", 195: "circumflex", 196: "tilde", 197: "macron",
      198: "breve", 199: "dotaccent", 200: "dieresis", 202: "ring", 203: "cedilla",
      205: "hungarumlaut", 206: "ogonek", 207: "caron", 208: "emdash", 225: "AE",
      227: "ordfeminine", 232: "Lslash", 233: "Oslash", 234: "OE", 235: "ordmasculine",
      241: "ae", 245: "dotlessi", 248: "lslash", 249: "oslash", 250: "oe",
      251: "germandbls",
    ]
    result.merge(high) { _, replacement in replacement }
    return result
  }()
}
