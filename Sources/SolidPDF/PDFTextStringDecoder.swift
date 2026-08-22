import Foundation

package enum PDFTextStringDecoder {
  package static func decode(_ string: PDFString, allowsUTF8: Bool) throws -> String {
    let bytes = [UInt8](string.bytes)
    if bytes.starts(with: [0xFE, 0xFF]) {
      return try decodeUTF16(Array(bytes.dropFirst(2)), littleEndian: false)
    }
    if bytes.starts(with: [0xFF, 0xFE]) {
      return try decodeUTF16(Array(bytes.dropFirst(2)), littleEndian: true)
    }
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      guard allowsUTF8,
        let value = String(data: Data(bytes.dropFirst(3)), encoding: .utf8)
      else { throw malformed("A PDF text string contains invalid UTF-8.") }
      return value
    }
    var scalars = String.UnicodeScalarView()
    for byte in bytes {
      guard byte != 0x9E, byte != 0x9F else {
        throw malformed("A PDF text string contains an undefined PDFDocEncoding byte.")
      }
      guard let scalar = UnicodeScalar(pdfDocEncoding[Int(byte)]) else {
        throw malformed("A PDF text string contains an undefined PDFDocEncoding byte.")
      }
      scalars.append(scalar)
    }
    return String(scalars)
  }

  private static func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) throws -> String {
    guard bytes.count.isMultiple(of: 2) else {
      throw malformed("A PDF UTF-16 text string has an odd byte count.")
    }
    let encoding: String.Encoding = littleEndian ? .utf16LittleEndian : .utf16BigEndian
    guard let value = String(data: Data(bytes), encoding: encoding) else {
      throw malformed("A PDF UTF-16 text string contains an invalid scalar sequence.")
    }
    return value
  }

  private static func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  private static let pdfDocEncoding: [UInt32] = {
    var table = (0...255).map(UInt32.init)
    let specials: [Int: UInt32] = [
      0x18: 0x02D8, 0x19: 0x02C7, 0x1A: 0x02C6, 0x1B: 0x02D9,
      0x1C: 0x02DD, 0x1D: 0x02DB, 0x1E: 0x02DA, 0x1F: 0x02DC,
      0x7F: 0x2022, 0x80: 0x2020, 0x81: 0x2021, 0x82: 0x2026,
      0x83: 0x2014, 0x84: 0x2013, 0x85: 0x0192, 0x86: 0x2044,
      0x87: 0x2039, 0x88: 0x203A, 0x89: 0x2212, 0x8A: 0x2030,
      0x8B: 0x201E, 0x8C: 0x201C, 0x8D: 0x201D, 0x8E: 0x2018,
      0x8F: 0x2019, 0x90: 0x201A, 0x91: 0x2122, 0x92: 0xFB01,
      0x93: 0xFB02, 0x94: 0x0141, 0x95: 0x0152, 0x96: 0x0160,
      0x97: 0x0178, 0x98: 0x017D, 0x99: 0x0131, 0x9A: 0x0142,
      0x9B: 0x0153, 0x9C: 0x0161, 0x9D: 0x017E, 0xA0: 0x20AC,
    ]
    for (index, scalar) in specials { table[index] = scalar }
    table[0x9E] = 0xFFFD
    table[0x9F] = 0xFFFD
    return table
  }()
}
