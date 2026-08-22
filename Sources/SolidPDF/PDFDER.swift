import Foundation

struct PDFDERNode: Sendable {
  enum TagClass: UInt8, Sendable {
    case universal = 0
    case application = 1
    case contextSpecific = 2
    case `private` = 3
  }

  let tagClass: TagClass
  let tagNumber: Int
  let isConstructed: Bool
  let fullRange: Range<Int>
  let contentRange: Range<Int>
  let children: [PDFDERNode]

  func bytes(in data: Data) -> Data { data.subdata(in: fullRange) }
  func content(in data: Data) -> Data { data.subdata(in: contentRange) }
}

struct PDFDERParser {
  private let data: Data
  private let maximumDepth: Int
  private let maximumNodes: Int
  private var nodeCount = 0

  init(data: Data, maximumDepth: Int, maximumNodes: Int) {
    self.data = data
    self.maximumDepth = maximumDepth
    self.maximumNodes = maximumNodes
  }

  mutating func parseOne() throws -> PDFDERNode {
    var offset = 0
    let node = try parse(at: &offset, limit: data.count, depth: 0)
    guard offset == data.count else { throw PDFDERError.trailingData(offset) }
    return node
  }

  mutating func parsePrefix() throws -> PDFDERNode {
    var offset = 0
    return try parse(at: &offset, limit: data.count, depth: 0)
  }

  private mutating func parse(at offset: inout Int, limit: Int, depth: Int) throws -> PDFDERNode {
    guard depth <= maximumDepth else { throw PDFDERError.limitExceeded }
    nodeCount += 1
    guard nodeCount <= maximumNodes else { throw PDFDERError.limitExceeded }
    let start = offset
    let first = try readByte(at: &offset, limit: limit)
    guard let tagClass = PDFDERNode.TagClass(rawValue: first >> 6) else {
      throw PDFDERError.malformed(start)
    }
    let constructed = first & 0x20 != 0
    var tagNumber = Int(first & 0x1F)
    if tagNumber == 0x1F {
      tagNumber = 0
      var consumed = 0
      while true {
        let byte = try readByte(at: &offset, limit: limit)
        guard consumed > 0 || byte & 0x7F != 0 else { throw PDFDERError.malformed(offset - 1) }
        let (shifted, overflow) = tagNumber.multipliedReportingOverflow(by: 128)
        let (next, additionOverflow) = shifted.addingReportingOverflow(Int(byte & 0x7F))
        guard !overflow, !additionOverflow else { throw PDFDERError.limitExceeded }
        tagNumber = next
        consumed += 1
        guard consumed <= MemoryLayout<Int>.size + 1 else { throw PDFDERError.limitExceeded }
        if byte & 0x80 == 0 { break }
      }
    }
    let firstLength = try readByte(at: &offset, limit: limit)
    let length: Int
    if firstLength & 0x80 == 0 {
      length = Int(firstLength)
    } else {
      let byteCount = Int(firstLength & 0x7F)
      guard byteCount > 0, byteCount <= MemoryLayout<Int>.size else {
        throw PDFDERError.malformed(offset - 1)
      }
      guard offset + byteCount <= limit, data[offset] != 0 else { throw PDFDERError.malformed(offset) }
      var value = 0
      for _ in 0..<byteCount {
        let byte = try readByte(at: &offset, limit: limit)
        let (shifted, overflow) = value.multipliedReportingOverflow(by: 256)
        let (next, additionOverflow) = shifted.addingReportingOverflow(Int(byte))
        guard !overflow, !additionOverflow else { throw PDFDERError.limitExceeded }
        value = next
      }
      guard value >= 128 else { throw PDFDERError.malformed(offset - byteCount) }
      length = value
    }
    let contentStart = offset
    let (contentEnd, overflow) = contentStart.addingReportingOverflow(length)
    guard !overflow, contentEnd <= limit else { throw PDFDERError.truncated(contentStart) }
    var children = [PDFDERNode]()
    if constructed {
      while offset < contentEnd {
        children.append(try parse(at: &offset, limit: contentEnd, depth: depth + 1))
      }
      guard offset == contentEnd else { throw PDFDERError.malformed(offset) }
    } else {
      offset = contentEnd
    }
    return PDFDERNode(
      tagClass: tagClass,
      tagNumber: tagNumber,
      isConstructed: constructed,
      fullRange: start..<contentEnd,
      contentRange: contentStart..<contentEnd,
      children: children
    )
  }

  private func readByte(at offset: inout Int, limit: Int) throws -> UInt8 {
    guard offset < limit else { throw PDFDERError.truncated(offset) }
    defer { offset += 1 }
    return data[offset]
  }
}

enum PDFDERError: Error {
  case malformed(Int)
  case truncated(Int)
  case trailingData(Int)
  case limitExceeded
}

extension PDFDERNode {
  func requireUniversal(_ number: Int) throws {
    guard tagClass == .universal, tagNumber == number else { throw PDFDERError.malformed(fullRange.lowerBound) }
  }

  func objectIdentifier(in data: Data) throws -> String {
    try requireUniversal(6)
    let bytes = [UInt8](data[contentRange])
    guard let first = bytes.first else { throw PDFDERError.malformed(contentRange.lowerBound) }
    var components = [Int(first) / 40, Int(first) % 40]
    var value = 0
    var pending = false
    for byte in bytes.dropFirst() {
      pending = true
      let (shifted, overflow) = value.multipliedReportingOverflow(by: 128)
      let (next, additionOverflow) = shifted.addingReportingOverflow(Int(byte & 0x7F))
      guard !overflow, !additionOverflow else { throw PDFDERError.limitExceeded }
      value = next
      if byte & 0x80 == 0 {
        components.append(value)
        value = 0
        pending = false
      }
    }
    guard !pending else { throw PDFDERError.truncated(contentRange.upperBound) }
    return components.map(String.init).joined(separator: ".")
  }

  func unsignedInteger(in data: Data) throws -> Data {
    try requireUniversal(2)
    var bytes = Data(data[contentRange])
    guard !bytes.isEmpty, bytes.first! & 0x80 == 0 else { throw PDFDERError.malformed(contentRange.lowerBound) }
    while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
    return bytes
  }
}
