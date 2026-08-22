import Foundation

enum PDFPasswordProcessing {
  static func bytes(_ password: PDFPassword, revision: Int) throws -> Data {
    switch password.storage {
    case .bytes(let bytes):
      return revision >= 5 ? Data(bytes.prefix(127)) : bytes
    case .unicode(let value):
      if revision == 6 { return try PDFSASLprep.prepare(value) }
      if revision == 5 { return Data(value.utf8.prefix(127)) }
      return try pdfDocEncoding(value)
    }
  }

  private static func pdfDocEncoding(_ value: String) throws -> Data {
    var result = Data()
    for scalar in value.unicodeScalars {
      if let byte = pdfDocByte(for: scalar.value) {
        result.append(byte)
      } else {
        throw PDFParsingError.malformed(
          .init(offset: 0, message: "A legacy password is not representable in PDFDocEncoding.")
        )
      }
    }
    return result
  }

  private static func pdfDocByte(for scalar: UInt32) -> UInt8? {
    if scalar <= 0x17 { return UInt8(scalar) }
    if (0x20...0x7E).contains(scalar) { return UInt8(scalar) }
    if (0xA1...0xFF).contains(scalar) { return UInt8(scalar) }
    return specialPDFDocBytes[scalar]
  }

  private static let specialPDFDocBytes: [UInt32: UInt8] = [
    0x02D8: 0x18, 0x02C7: 0x19, 0x02C6: 0x1A, 0x02D9: 0x1B,
    0x02DD: 0x1C, 0x02DB: 0x1D, 0x02DA: 0x1E, 0x02DC: 0x1F,
    0x2022: 0x7F, 0x2020: 0x80, 0x2021: 0x81, 0x2026: 0x82,
    0x2014: 0x83, 0x2013: 0x84, 0x0192: 0x85, 0x2044: 0x86,
    0x2039: 0x87, 0x203A: 0x88, 0x2212: 0x89, 0x2030: 0x8A,
    0x201E: 0x8B, 0x201C: 0x8C, 0x201D: 0x8D, 0x2018: 0x8E,
    0x2019: 0x8F, 0x201A: 0x90, 0x2122: 0x91, 0xFB01: 0x92,
    0xFB02: 0x93, 0x0141: 0x94, 0x0152: 0x95, 0x0160: 0x96,
    0x0178: 0x97, 0x017D: 0x98, 0x0131: 0x99, 0x0142: 0x9A,
    0x0153: 0x9B, 0x0161: 0x9C, 0x017E: 0x9D, 0x20AC: 0xA0,
  ]
}
