import Foundation

package struct ConformanceTranscript: Codable, Sendable, Hashable {
  package static let header = "SPS-CONFORMANCE 1"

  package let records: [Record]

  package struct Record: Codable, Sendable, Hashable {
    package let label: Data
    package let value: Value
  }

  package enum Value: Codable, Sendable, Hashable {
    case null
    case boolean(Bool)
    case integer(Int64)
    case real(Double)
    case name(Data)
    case string(Data)
    case arrayCount(Int)
  }

  package static func parse(_ data: Data, maximumBytes: Int) throws -> Self {
    guard data.count <= maximumBytes else { throw ConformanceError.transcriptLimitExceeded }
    guard let text = String(data: data, encoding: .isoLatin1) else {
      throw ConformanceError.malformedTranscript("output is not ISO Latin-1")
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" { lines.removeLast() }
    guard lines.first == header else { throw ConformanceError.malformedTranscript("missing version header") }
    var records: [Record] = []
    for (index, line) in lines.dropFirst().enumerated() {
      guard !line.isEmpty else { continue }
      let fields = line.split(separator: " ", omittingEmptySubsequences: false)
      guard fields.count == 4, fields[0] == "V", let label = Data(hex: fields[1]) else {
        throw ConformanceError.malformedTranscript("invalid record at line \(index + 2)")
      }
      let payload = fields[3]
      let value: Value
      switch fields[2] {
      case "null":
        guard payload == "-" else { throw ConformanceError.malformedTranscript("invalid null payload") }
        value = .null
      case "boolean":
        guard payload == "true" || payload == "false" else {
          throw ConformanceError.malformedTranscript("invalid boolean payload")
        }
        value = .boolean(payload == "true")
      case "integer":
        guard let parsed = Int64(payload) else { throw ConformanceError.malformedTranscript("invalid integer payload") }
        value = .integer(parsed)
      case "real":
        guard let parsed = Double(payload), parsed.isFinite else {
          throw ConformanceError.malformedTranscript("invalid real payload")
        }
        value = .real(parsed == 0 ? 0 : parsed)
      case "name":
        guard let parsed = Data(hex: payload) else { throw ConformanceError.malformedTranscript("invalid name payload") }
        value = .name(parsed)
      case "string":
        guard let parsed = Data(hex: payload) else { throw ConformanceError.malformedTranscript("invalid string payload") }
        value = .string(parsed)
      case "array":
        guard let count = Int(payload), count >= 0 else {
          throw ConformanceError.malformedTranscript("invalid array payload")
        }
        value = .arrayCount(count)
      default:
        throw ConformanceError.malformedTranscript("unknown value type \(fields[2])")
      }
      records.append(Record(label: label, value: value))
    }
    return Self(records: records)
  }

  package func isEquivalent(to other: Self, realTolerance: Double = 1e-9) -> Bool {
    guard records.count == other.records.count else { return false }
    return zip(records, other.records).allSatisfy { left, right in
      guard left.label == right.label else { return false }
      switch (left.value, right.value) {
      case (.real(let lhs), .real(let rhs)):
        return abs(lhs - rhs) <= realTolerance * max(1, abs(lhs), abs(rhs))
      default:
        return left.value == right.value
      }
    }
  }
}

private extension Data {
  init?<S: StringProtocol>(hex: S) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var result = Data()
    result.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      result.append(byte)
      index = next
    }
    self = result
  }
}
