enum PDFCheckedArithmetic {
  static func add(_ lhs: Int, _ rhs: Int, offset: Int64) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw limit(offset, "Integer addition overflowed.") }
    return result
  }

  static func multiply(_ lhs: Int, _ rhs: Int, offset: Int64) throws -> Int {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    guard !overflow else { throw limit(offset, "Integer multiplication overflowed.") }
    return result
  }

  static func add(_ lhs: Int64, _ rhs: Int64, offset: Int64) throws -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw limit(offset, "Source offset overflowed.") }
    return result
  }

  private static func limit(_ offset: Int64, _ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: offset, message: message))
  }
}
