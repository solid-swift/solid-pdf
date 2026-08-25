import Foundation

enum PDFSASLprep {
  static func prepare(_ value: String) throws -> Data {
    var mapped = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      if mapsToNothing(scalar.value) { continue }
      if mapsToSpace(scalar.value) {
        mapped.append(" ")
      } else {
        mapped.append(scalar)
      }
    }
    let normalized = String(mapped).precomposedStringWithCompatibilityMapping
    let scalars = Array(normalized.unicodeScalars)
    guard scalars.allSatisfy({ !isProhibited($0) }), obeysBidirectionalRule(scalars) else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "A password contains a character prohibited by SASLprep.")
      )
    }
    return Data(normalized.utf8.prefix(127))
  }

  private static func mapsToNothing(_ value: UInt32) -> Bool {
    value == 0x00AD || value == 0x034F || value == 0x1806
      || (0x180B...0x180D).contains(value)
      || (0x200B...0x200D).contains(value)
      || value == 0x2060 || (0xFE00...0xFE0F).contains(value) || value == 0xFEFF
  }

  private static func mapsToSpace(_ value: UInt32) -> Bool {
    value == 0x00A0 || value == 0x1680 || (0x2000...0x200B).contains(value)
      || value == 0x202F || value == 0x205F || value == 0x3000
  }

  private static func isProhibited(_ scalar: Unicode.Scalar) -> Bool {
    let value = scalar.value
    if PDFUnicode32Tables.isUnassigned(value) { return true }
    if value <= 0x1F || (0x7F...0x9F).contains(value) { return true }
    if value == 0x06DD || value == 0x070F || value == 0x180E
      || (0x2028...0x2029).contains(value) || (0x2061...0x2063).contains(value)
      || (0x1D173...0x1D17A).contains(value)
    { return true }
    if (0xE000...0xF8FF).contains(value) || (0xF0000...0xFFFFD).contains(value)
      || (0x100000...0x10FFFD).contains(value)
    { return true }
    if (0xD800...0xDFFF).contains(value) || (0xFFF9...0xFFFD).contains(value) { return true }
    if (0xFDD0...0xFDEF).contains(value) || (value & 0xFFFF) >= 0xFFFE { return true }
    if (0x2FF0...0x2FFB).contains(value) || value == 0x0340 || value == 0x0341
      || value == 0x200E || value == 0x200F || (0x202A...0x202E).contains(value)
      || (0x206A...0x206F).contains(value) || value == 0xE0001
      || (0xE0020...0xE007F).contains(value)
    { return true }
    return false
  }

  private static func obeysBidirectionalRule(_ scalars: [Unicode.Scalar]) -> Bool {
    let hasRandAL = scalars.contains { PDFUnicode32BidiTables.isRandAL($0.value) }
    guard hasRandAL else { return true }
    let hasL = scalars.contains { PDFUnicode32BidiTables.isL($0.value) }
    guard !hasL, let first = scalars.first?.value, let last = scalars.last?.value else { return false }
    return PDFUnicode32BidiTables.isRandAL(first) && PDFUnicode32BidiTables.isRandAL(last)
  }
}
