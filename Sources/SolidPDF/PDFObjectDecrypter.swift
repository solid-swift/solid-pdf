enum PDFObjectDecrypter {
  static func decrypt(
    _ object: PDFObject,
    in reference: PDFObjectReference,
    using context: PDFSecurityContext
  ) throws -> PDFObject {
    switch object {
    case .string(let string):
      return .string(
        PDFString(
          bytes: try context.decryptString(string.bytes, in: reference),
          representation: string.representation
        )
      )
    case .array(let values):
      return .array(try values.map { try decrypt($0, in: reference, using: context) })
    case .dictionary(let dictionary):
      return .dictionary(
        try dictionary.mapValues { try decrypt($0, in: reference, using: context) }
      )
    default:
      return object
    }
  }
}
