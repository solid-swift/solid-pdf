import Foundation

struct IODeviceResources: ResourceCategory {
  static let instance = Self(fileDevices: FileDevices())

  let fileDevices: FileDevices

  var dictionary: ResourceCategoryDictionary {
    .init(category: "IODevice", instanceType: .string)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ImplicitResourceValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    guard let identifier = try identifier(for: key), contains(identifier) else { return nil }
    return (true, 0)
  }

  func loadResource(forKey key: Object, in context: isolated Context) throws -> Object {
    guard let identifier = try identifier(for: key), contains(identifier) else {
      throw Error.undefinedResource
    }
    return .string(identifier, access: .readOnly, vm: .global, kind: .literal)
  }

  func sizeOfResource(_ instance: Object) throws -> Int { 0 }

  func enumerateResources(matching template: String) throws -> [Object] {
    guard let regex = template.asTemplateRegex else { return [] }
    return fileDevices.registeredDevices.compactMap { device in
      let identifier = "%\(device.name)%"
      guard (try? regex.wholeMatch(in: identifier)) != nil else { return nil }
      return .string(identifier, access: .readOnly, vm: .global, kind: .literal)
    }
  }

  private func identifier(for key: Object) throws -> String? {
    guard let value = key.value as? NameStringConvertible else { return nil }
    if let string = key.value as? StringValue {
      try string.access.check(.read)
    }
    return value.nameString
  }

  private func contains(_ identifier: String) -> Bool {
    let name = identifier
      .trimmingPrefix("%")
      .trimmingSuffix("%")
    return fileDevices.registeredDevices.contains { $0.name == name }
  }
}

private extension String {
  func trimmingPrefix(_ prefix: Character) -> String {
    first == prefix ? String(dropFirst()) : self
  }

  func trimmingSuffix(_ suffix: Character) -> String {
    last == suffix ? String(dropLast()) : self
  }
}
