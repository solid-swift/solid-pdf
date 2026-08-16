import Foundation

enum ObjectFormat: Int32, Sendable {
  case disabled = 0
  case ieeeBigEndian = 1
  case ieeeLittleEndian = 2
  case nativeBigEndian = 3
  case nativeLittleEndian = 4

  enum ByteOrder {
    case bigEndian
    case littleEndian
  }

  enum RealFormat {
    case ieee
    case native
  }

  init(validating value: Int32) throws {
    guard let format = Self(rawValue: value) else {
      throw Error.rangeCheck
    }
    self = format
  }

  var binaryEnabled: Bool { self != .disabled }

  var byteOrder: ByteOrder {
    switch self {
    case .disabled, .ieeeBigEndian, .nativeBigEndian:
      .bigEndian
    case .ieeeLittleEndian, .nativeLittleEndian:
      .littleEndian
    }
  }

  var realFormat: RealFormat {
    switch self {
    case .disabled, .ieeeBigEndian, .ieeeLittleEndian:
      .ieee
    case .nativeBigEndian, .nativeLittleEndian:
      .native
    }
  }

  var sequenceToken: UInt8 {
    switch self {
    case .disabled: 0
    case .ieeeBigEndian: 128
    case .ieeeLittleEndian: 129
    case .nativeBigEndian: 130
    case .nativeLittleEndian: 131
    }
  }
}
