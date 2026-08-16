//
//  PostScriptTextFormatter.swift
//

import Foundation

struct PostScriptTextFormatter {

  enum Mode {
    case value
    case syntax
  }

  private static let fallback = Data("--nostringval--".utf8)
  private static let maximumDepth = 64

  let mode: Mode
  private var activeArrays = Set<ObjectIdentifier>()

  init(mode: Mode) {
    self.mode = mode
  }

  mutating func format(_ object: Object) -> Data {
    switch mode {
    case .value:
      value(object)
    case .syntax:
      syntax(object, depth: 0)
    }
  }

  private func value(_ object: Object) -> Data {
    switch object.value {
    case let value as IntegerValue:
      ascii(String(value.value))
    case let value as RealValue:
      ascii(String(value.value).replacingOccurrences(of: "e", with: "E"))
    case let value as BooleanValue:
      ascii(value.value ? "true" : "false")
    case let value as StringValue where value.access.isReadAllowed:
      (try? value.characters(in: value.range)) ?? Self.fallback
    case let value as NameValue:
      ascii(value.value)
    case let value as any OperatorValue:
      ascii(value.systemDictionaryNames.first?.valueString ?? "--nostringval--")
    default:
      Self.fallback
    }
  }

  private mutating func syntax(_ object: Object, depth: Int) -> Data {
    switch object.value {
    case let value as IntegerValue:
      return ascii(String(value.value))
    case let value as RealValue:
      return ascii(String(value.value).replacingOccurrences(of: "e", with: "E"))
    case let value as BooleanValue:
      return ascii(value.value ? "true" : "false")
    case let value as NameValue:
      return ascii(object.kind == .literal ? "/" + value.value : value.value)
    case let value as StringValue:
      guard value.access.isReadAllowed, let characters = try? value.characters(in: value.range) else {
        return opaque(object)
      }
      return escapedString(characters)
    case let value as ArrayValue:
      guard value.access.isReadAllowed, depth < Self.maximumDepth else { return opaque(object) }
      let identity = value.snapshotIdentity
      guard activeArrays.insert(identity).inserted else { return opaque(object) }
      defer { activeArrays.remove(identity) }
      guard let objects = try? value.objects(in: value.range, for: .read) else { return opaque(object) }
      return collection(Array(objects), kind: object.kind, depth: depth)
    case let value as PackedArrayValue:
      guard value.access.isReadAllowed, depth < Self.maximumDepth else { return opaque(object) }
      return collection(value.elements, kind: object.kind, depth: depth)
    case let value as any OperatorValue:
      let name = value.systemDictionaryNames.first?.valueString ?? "nostringval"
      return ascii("--\(name)--")
    case is NullValue:
      return ascii("null")
    default:
      return opaque(object)
    }
  }

  private mutating func collection(_ objects: [Object], kind: ObjectKind, depth: Int) -> Data {
    var result = Data(kind == .executable ? "{".utf8 : "[".utf8)
    for (index, object) in objects.enumerated() {
      if index > 0 { result.append(0x20) }
      result.append(syntax(object, depth: depth + 1))
    }
    result.append(contentsOf: kind == .executable ? "}".utf8 : "]".utf8)
    return result
  }

  private func escapedString(_ data: Data) -> Data {
    var result = Data([0x28])
    for byte in data {
      switch byte {
      case 0x28, 0x29, 0x5C:
        result.append(0x5C)
        result.append(byte)
      case 0x0A:
        result.append(contentsOf: "\\n".utf8)
      case 0x0D:
        result.append(contentsOf: "\\r".utf8)
      case 0x09:
        result.append(contentsOf: "\\t".utf8)
      case 0x08:
        result.append(contentsOf: "\\b".utf8)
      case 0x0C:
        result.append(contentsOf: "\\f".utf8)
      case 0x20...0x7E:
        result.append(byte)
      default:
        result.append(0x5C)
        result.append(contentsOf: String(format: "%03o", byte).utf8)
      }
    }
    result.append(0x29)
    return result
  }

  private func opaque(_ object: Object) -> Data {
    let type =
      switch object.type {
      case .dictionary: "dict"
      case .packedArray: "packedarray"
      default: String(object.type.name.dropLast("type".count))
      }
    return ascii("-\(type)-")
  }

  private func ascii(_ value: String) -> Data {
    value.data(using: .isoLatin1) ?? Data(value.utf8)
  }
}
