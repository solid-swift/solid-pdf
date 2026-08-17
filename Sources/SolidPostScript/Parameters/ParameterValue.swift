import Foundation

enum ParameterValue: Equatable, Sendable {
  case boolean(Bool)
  case integer(Int32)
  case string(Data)

  var allocationFootprint: Int {
    switch self {
    case .string(let value):
      let (footprint, overflow) = value.count.addingReportingOverflow(16)
      return overflow ? .max : footprint
    default:
      return 0
    }
  }

  func object(vm: VM) -> Object {
    switch self {
    case .boolean(let value):
      .boolean(value)
    case .integer(let value):
      .integer(value)
    case .string(let value):
      .string(value, access: .unlimited, vm: vm, kind: .literal)
    }
  }

  static func boolean(from object: Object) throws -> Self {
    .boolean(try object.value(as: BooleanValue.self).value)
  }

  static func integer(from object: Object) throws -> Int32 {
    try object.value(as: IntegerValue.self).value
  }

  static func string(from object: Object, maximumLength: Int? = nil) throws -> Self {
    let string = try object.value(as: StringValue.self)
    var data = try string.characters(in: string.range)
    if let null = data.firstIndex(of: 0) {
      data = data[..<null]
    }
    if let maximumLength, data.count > maximumLength {
      data = data.prefix(maximumLength)
    }
    return .string(Data(data))
  }

  static func password(from object: Object) throws -> Data {
    switch object.value {
    case let value as StringValue:
      return try value.characters(in: value.range)
    case let value as IntegerValue:
      return Data(String(value.value).utf8)
    default:
      throw Error.typeCheck
    }
  }
}
