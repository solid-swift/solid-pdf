/// Adobe Glyph List name interpretation used for document text metadata.
public enum AdobeGlyphList {
  /// Returns Unicode scalars represented by an Adobe glyph name.
  ///
  /// The algorithm removes stylistic suffixes, expands underscore-separated
  /// ligatures, recognizes `uniXXXX` and `uXXXXX` names, and then consults the
  /// standard Adobe names used by PostScript base encodings.
  public static func unicodeScalars(for glyphName: String) -> [Unicode.Scalar]? {
    let base = glyphName.split(separator: ".", maxSplits: 1).first.map(String.init) ?? glyphName
    if base.contains("_") {
      let parts = base.split(separator: "_")
      let values = parts.compactMap { unicodeScalars(for: String($0)) }
      guard values.count == parts.count else { return nil }
      return values.flatMap { $0 }
    }
    if base.hasPrefix("uni"), base.count > 3 {
      let digits = String(base.dropFirst(3))
      guard digits.count.isMultiple(of: 4) else { return nil }
      var result: [Unicode.Scalar] = []
      var index = digits.startIndex
      while index < digits.endIndex {
        let end = digits.index(index, offsetBy: 4)
        guard let value = UInt32(digits[index..<end], radix: 16),
          let scalar = Unicode.Scalar(value), !(0xD800...0xDFFF).contains(value)
        else { return nil }
        result.append(scalar)
        index = end
      }
      return result
    }
    if base.hasPrefix("u"), (5...7).contains(base.count),
      let value = UInt32(base.dropFirst(), radix: 16),
      let scalar = Unicode.Scalar(value), !(0xD800...0xDFFF).contains(value)
    {
      return [scalar]
    }
    if base.count == 1, let scalar = base.unicodeScalars.first { return [scalar] }
    guard let value = standardNames[base], let scalar = Unicode.Scalar(value) else { return nil }
    return [scalar]
  }

  private static let standardNames: [String: UInt32] = [
    "space": 0x0020, "exclam": 0x0021, "quotedbl": 0x0022, "numbersign": 0x0023,
    "dollar": 0x0024, "percent": 0x0025, "ampersand": 0x0026, "quotesingle": 0x0027,
    "parenleft": 0x0028, "parenright": 0x0029, "asterisk": 0x002A, "plus": 0x002B,
    "comma": 0x002C, "hyphen": 0x002D, "period": 0x002E, "slash": 0x002F,
    "zero": 0x0030, "one": 0x0031, "two": 0x0032, "three": 0x0033,
    "four": 0x0034, "five": 0x0035, "six": 0x0036, "seven": 0x0037,
    "eight": 0x0038, "nine": 0x0039, "colon": 0x003A, "semicolon": 0x003B,
    "less": 0x003C, "equal": 0x003D, "greater": 0x003E, "question": 0x003F,
    "at": 0x0040, "bracketleft": 0x005B, "backslash": 0x005C, "bracketright": 0x005D,
    "asciicircum": 0x005E, "underscore": 0x005F, "grave": 0x0060,
    "braceleft": 0x007B, "bar": 0x007C, "braceright": 0x007D, "asciitilde": 0x007E,
    "nbspace": 0x00A0, "exclamdown": 0x00A1, "cent": 0x00A2, "sterling": 0x00A3,
    "yen": 0x00A5, "section": 0x00A7, "copyright": 0x00A9, "registered": 0x00AE,
    "degree": 0x00B0, "plusminus": 0x00B1, "paragraph": 0x00B6, "periodcentered": 0x00B7,
    "questiondown": 0x00BF, "AE": 0x00C6, "Oslash": 0x00D8, "ae": 0x00E6,
    "oslash": 0x00F8, "OE": 0x0152, "oe": 0x0153, "Scaron": 0x0160,
    "scaron": 0x0161, "Ydieresis": 0x0178, "Zcaron": 0x017D, "zcaron": 0x017E,
    "florin": 0x0192, "circumflex": 0x02C6, "caron": 0x02C7, "breve": 0x02D8,
    "dotaccent": 0x02D9, "ring": 0x02DA, "ogonek": 0x02DB, "tilde": 0x02DC,
    "hungarumlaut": 0x02DD, "endash": 0x2013, "emdash": 0x2014,
    "quoteleft": 0x2018, "quoteright": 0x2019, "quotesinglbase": 0x201A,
    "quotedblleft": 0x201C, "quotedblright": 0x201D, "quotedblbase": 0x201E,
    "dagger": 0x2020, "daggerdbl": 0x2021, "bullet": 0x2022, "ellipsis": 0x2026,
    "perthousand": 0x2030, "guilsinglleft": 0x2039, "guilsinglright": 0x203A,
    "fraction": 0x2044, "Euro": 0x20AC, "trademark": 0x2122, "minus": 0x2212,
    "fi": 0xFB01, "fl": 0xFB02,
  ]
}
