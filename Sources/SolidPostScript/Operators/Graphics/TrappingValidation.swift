import Foundation

extension Operators {
  static func trappingIntegerArray(_ object: Object) throws -> [Int32] {
    let objects: [Object]
    if let array = object.value as? ArrayValue {
      objects = Array(try array.objects(in: array.range, for: .read))
    } else if let array = object.value as? PackedArrayValue {
      objects = Array(try array.objects(in: array.range, for: .read))
    } else {
      throw Error.typeCheck
    }
    return try objects.map { try $0.value(as: IntegerValue.self).value }
  }

  static func validateTrapParameterDictionary(_ dictionary: DictionaryValue) throws {
    try dictionary.access.check(.read)
    try dictionary.forEachUnchecked { key, value in
      let name = try key.value(as: NameValue.self).value
      switch name {
      case "TrapSetName":
        guard value.value is StringValue else { throw Error.typeCheck }
        try value.value(as: StringValue.self).access.check(.read)
      case "Enabled", "ImageToObjectTrapping", "ImageInternalTrapping":
        _ = try value.value(as: BooleanValue.self)
      case "StepLimit", "BlackColorLimit":
        let number = try trappingNumber(value)
        guard (0...1).contains(number) else { throw Error.rangeCheck }
      case "TrapWidth":
        guard try trappingNumber(value) >= 0 else { throw Error.rangeCheck }
      case "TrapColorScaling", "BlackWidth", "SlidingTrapLimit":
        guard try trappingNumber(value) >= 0 else { throw Error.rangeCheck }
      case "BlackDensityLimit":
        guard try trappingNumber(value) >= 0 else { throw Error.rangeCheck }
      case "ImageResolution":
        guard try trappingNumber(value) > 0 else { throw Error.rangeCheck }
      case "ImageTrapPlacement":
        let name = try value.value(as: NameValue.self).value
        guard GraphicsImageTrapPlacement(rawValue: name) != nil else { throw Error.rangeCheck }
      case "ColorantZoneDetails":
        let details = try value.value(as: DictionaryValue.self)
        try details.access.check(.read)
        try details.forEachUnchecked { colorant, parameters in
          _ = try colorant.value(as: NameValue.self)
          let dictionary = try parameters.value(as: DictionaryValue.self)
          try dictionary.access.check(.read)
          try dictionary.forEachUnchecked { parameter, setting in
            switch try parameter.value(as: NameValue.self).value {
            case "StepLimit":
              guard (0...1).contains(try trappingNumber(setting)) else { throw Error.rangeCheck }
            case "TrapColorScaling":
              guard try trappingNumber(setting) >= 0 else { throw Error.rangeCheck }
            default:
              break
            }
          }
        }
      default:
        break
      }
    }
  }

  static func trappingNumber(_ object: Object) throws -> Double {
    let value: Double = switch object.value {
    case let integer as IntegerValue: Double(integer.value)
    case let real as RealValue: real.value
    default: throw Error.typeCheck
    }
    guard value.isFinite else { throw Error.rangeCheck }
    return value
  }
}
