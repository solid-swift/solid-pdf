import Foundation
import SolidPDF

enum PDFObjectAccess {
  static func number(_ object: PDFObject) throws -> Double {
    switch object {
    case .number(.integer(let value)): Double(value)
    case .number(.real(let value)): value
    default: throw TypeMismatch.number
    }
  }

  static func integer(_ object: PDFObject) throws -> Int {
    guard case .number(.integer(let value)) = object, let result = Int(exactly: value) else {
      throw TypeMismatch.integer
    }
    return result
  }

  static func name(_ object: PDFObject) throws -> PDFName {
    guard case .name(let value) = object else { throw TypeMismatch.name }
    return value
  }

  static func array(_ object: PDFObject) throws -> [PDFObject] {
    guard case .array(let value) = object else { throw TypeMismatch.array }
    return value
  }

  static func dictionary(_ object: PDFObject) throws -> [PDFName: PDFObject] {
    guard case .dictionary(let value) = object else { throw TypeMismatch.dictionary }
    return value
  }

  static func numbers(_ object: PDFObject) throws -> [Double] {
    try array(object).map(number)
  }

  enum TypeMismatch: Error {
    case number
    case integer
    case name
    case array
    case dictionary
  }
}

extension PDFName {
  var pdfGraphicsString: String { String(decoding: bytes, as: UTF8.self) }
}
