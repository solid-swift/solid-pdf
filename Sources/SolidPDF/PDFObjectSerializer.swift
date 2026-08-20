import Foundation

struct PDFObjectSerializer {
  let limits: PDFWritingLimits

  func serialize(_ object: PDFObject) throws -> Data {
    var output = Data()
    try append(object, depth: 0, to: &output)
    return output
  }

  func references(in object: PDFObject) throws -> Set<PDFObjectReference> {
    var references = Set<PDFObjectReference>()
    try collectReferences(object, depth: 0, into: &references)
    return references
  }

  private func append(_ object: PDFObject, depth: Int, to output: inout Data) throws {
    guard depth <= limits.maximumObjectNesting else { throw PDFError.limitExceeded }
    switch object {
    case .null:
      output.appendASCII("null")
    case .boolean(let value):
      output.appendASCII(value ? "true" : "false")
    case .number(let number):
      switch number {
      case .integer(let value): output.appendASCII(String(value))
      case .real(let value): output.appendASCII(try Self.real(value))
      }
    case .name(let name):
      output.append(Self.name(name))
    case .string(let string):
      output.append(Self.string(string))
    case .array(let values):
      output.appendASCII("[")
      for (index, value) in values.enumerated() {
        if index != 0 { output.appendASCII(" ") }
        try append(value, depth: depth + 1, to: &output)
      }
      output.appendASCII("]")
    case .dictionary(let values):
      output.appendASCII("<<")
      for key in values.keys.sorted() {
        output.appendASCII("\n")
        output.append(Self.name(key))
        output.appendASCII(" ")
        guard let value = values[key] else { throw PDFError.invalidObject }
        try append(value, depth: depth + 1, to: &output)
      }
      if !values.isEmpty { output.appendASCII("\n") }
      output.appendASCII(">>")
    case .reference(let reference):
      guard reference.objectNumber > 0 else { throw PDFError.invalidReference }
      output.appendASCII("\(reference.objectNumber) 0 R")
    }
  }

  private func collectReferences(
    _ object: PDFObject,
    depth: Int,
    into references: inout Set<PDFObjectReference>
  ) throws {
    guard depth <= limits.maximumObjectNesting else { throw PDFError.limitExceeded }
    switch object {
    case .array(let values):
      for value in values {
        try collectReferences(value, depth: depth + 1, into: &references)
      }
    case .dictionary(let values):
      for value in values.values {
        try collectReferences(value, depth: depth + 1, into: &references)
      }
    case .reference(let reference):
      references.insert(reference)
    default:
      break
    }
  }

  private static func name(_ name: PDFName) -> Data {
    var result = Data([0x2F])
    for byte in name.bytes {
      if (33...126).contains(byte), !nameDelimiters.contains(byte), byte != 0x23 {
        result.append(byte)
      } else {
        result.append(0x23)
        result.appendASCII(String(format: "%02X", byte))
      }
    }
    return result
  }

  private static func string(_ string: PDFString) -> Data {
    let literalEligible = string.bytes.allSatisfy { byte in
      byte == 0x09 || byte == 0x0A || byte == 0x0D || (0x20...0x7E).contains(byte)
    }
    if string.representation == .hexadecimal
      || (string.representation == .automatic && !literalEligible)
    {
      var result = Data([0x3C])
      for byte in string.bytes { result.appendASCII(String(format: "%02X", byte)) }
      result.append(0x3E)
      return result
    }

    var result = Data([0x28])
    for byte in string.bytes {
      switch byte {
      case 0x28, 0x29, 0x5C:
        result.append(0x5C)
        result.append(byte)
      case 0x0A: result.appendASCII("\\n")
      case 0x0D: result.appendASCII("\\r")
      case 0x09: result.appendASCII("\\t")
      case 0x08: result.appendASCII("\\b")
      case 0x0C: result.appendASCII("\\f")
      default: result.append(byte)
      }
    }
    result.append(0x29)
    return result
  }

  private static func real(_ value: Double) throws -> String {
    guard value.isFinite else { throw PDFError.invalidObject }
    if value == 0 { return "0" }
    let source = String(value)
    guard let exponentIndex = source.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
      return source
    }
    let mantissa = String(source[..<exponentIndex])
    guard let exponent = Int(source[source.index(after: exponentIndex)...]) else {
      throw PDFError.invalidObject
    }
    let negative = mantissa.hasPrefix("-")
    let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
    let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
    let integer = String(parts[0])
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    let digits = integer + fraction
    let decimalIndex = integer.count + exponent
    let expanded: String
    if decimalIndex <= 0 {
      expanded = "0." + String(repeating: "0", count: -decimalIndex) + digits
    } else if decimalIndex >= digits.count {
      expanded = digits + String(repeating: "0", count: decimalIndex - digits.count)
    } else {
      let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
      expanded = String(digits[..<split]) + "." + String(digits[split...])
    }
    return negative ? "-" + expanded : expanded
  }

  private static let nameDelimiters = Set<UInt8>([0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25])
}

extension Data {
  mutating func appendASCII(_ string: String) {
    append(contentsOf: string.utf8)
  }
}
