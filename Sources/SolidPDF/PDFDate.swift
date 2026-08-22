import Foundation

/// The precision present in a PDF date string.
public enum PDFDatePrecision: Int, Sendable, Hashable, Comparable {
  case year
  case month
  case day
  case hour
  case minute
  case second

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Time-zone information retained from a PDF date string.
public enum PDFDateTimeZone: Sendable, Hashable {
  case unspecified
  case universal
  case offset(minutes: Int)
}

/// A parsed PDF date that retains its exact source spelling.
public struct PDFDate: Sendable, Hashable {
  /// The original PDF string.
  public let original: PDFString
  /// The finest date component supplied by the source.
  public let precision: PDFDatePrecision
  /// The source time-zone declaration.
  public let timeZone: PDFDateTimeZone
  /// The resolved instant when all required components and a time zone are present.
  public let instant: Date?
  /// The parsed calendar components.
  public let components: DateComponents

  /// Parses a PDF date string.
  public init(_ original: PDFString) throws {
    let text = String(decoding: original.bytes, as: UTF8.self)
    let source = text.hasPrefix("D:") ? String(text.dropFirst(2)) : text
    guard source.count >= 4 else { throw Self.malformed("A PDF date requires a four-digit year.") }
    let bytes = Array(source.utf8)
    func digits(_ start: Int, _ count: Int, _ name: String) throws -> Int? {
      guard start < bytes.count else { return nil }
      guard start + count <= bytes.count else { throw Self.malformed("A PDF date has a truncated \(name).") }
      var value = 0
      for byte in bytes[start..<(start + count)] {
        guard byte >= 0x30, byte <= 0x39 else { throw Self.malformed("A PDF date has a malformed \(name).") }
        value = value * 10 + Int(byte - 0x30)
      }
      return value
    }

    guard let year = try digits(0, 4, "year") else { throw Self.malformed("A PDF date requires a year.") }
    let month = try digits(4, 2, "month")
    let day = try digits(6, 2, "day")
    let hour = try digits(8, 2, "hour")
    let minute = try digits(10, 2, "minute")
    let second = try digits(12, 2, "second")
    let componentEnd = min(bytes.count, 14)
    let precision: PDFDatePrecision = if second != nil { .second }
      else if minute != nil { .minute }
      else if hour != nil { .hour }
      else if day != nil { .day }
      else if month != nil { .month }
      else { .year }

    var zone: PDFDateTimeZone = .unspecified
    if componentEnd < bytes.count {
      let marker = bytes[componentEnd]
      if marker == 0x5A {
        guard componentEnd + 1 == bytes.count else { throw Self.malformed("A UTC PDF date has trailing data.") }
        zone = .universal
      } else if marker == 0x2B || marker == 0x2D {
        guard componentEnd + 3 <= bytes.count,
          let zoneHour = try digits(componentEnd + 1, 2, "time-zone hour")
        else { throw Self.malformed("A PDF date has a truncated time-zone offset.") }
        var cursor = componentEnd + 3
        if cursor < bytes.count, bytes[cursor] == 0x27 { cursor += 1 }
        let zoneMinute = try digits(cursor, 2, "time-zone minute") ?? 0
        cursor += cursor < bytes.count ? 2 : 0
        if cursor < bytes.count, bytes[cursor] == 0x27 { cursor += 1 }
        guard cursor == bytes.count, zoneHour <= 23, zoneMinute <= 59 else {
          throw Self.malformed("A PDF date has an invalid time-zone offset.")
        }
        let magnitude = zoneHour * 60 + zoneMinute
        zone = .offset(minutes: marker == 0x2D ? -magnitude : magnitude)
      } else {
        throw Self.malformed("A PDF date has an invalid time-zone marker.")
      }
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    switch zone {
    case .unspecified: break
    case .universal: components.timeZone = TimeZone(secondsFromGMT: 0)
    case .offset(let minutes): components.timeZone = TimeZone(secondsFromGMT: minutes * 60)
    }
    if let month, !(1...12).contains(month) { throw Self.malformed("A PDF date month is outside its range.") }
    if let day, !(1...31).contains(day) { throw Self.malformed("A PDF date day is outside its range.") }
    if let hour, !(0...23).contains(hour) { throw Self.malformed("A PDF date hour is outside its range.") }
    if let minute, !(0...59).contains(minute) { throw Self.malformed("A PDF date minute is outside its range.") }
    if let second, !(0...59).contains(second) { throw Self.malformed("A PDF date second is outside its range.") }

    self.original = original
    self.precision = precision
    self.timeZone = zone
    self.components = components
    instant = precision == .second && components.timeZone != nil
      ? components.calendar?.date(from: components)
      : nil
  }

  private static func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }
}
