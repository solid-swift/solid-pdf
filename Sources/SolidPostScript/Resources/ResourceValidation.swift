import Foundation

enum ImplicitResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    throw Error.invalidAccess
  }

  func willUndefine(key: Object, instance: Object, context: isolated Context) throws {
    throw Error.invalidAccess
  }
}

enum CategoryResourceValidation: Operators.ResourceCategoryExtension {
  case instance

  private static let requiredProcedures: [Object] = [
    "DefineResource",
    "UndefineResource",
    "FindResource",
    "ResourceStatus",
    "ResourceForAll",
  ]

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    guard context.allocationMode == .global else { throw Error.invalidAccess }
    let categoryName = try canonicalResourceKey(key).value(as: NameValue.self)
    let dictionary = try instance.value(as: DictionaryValue.self)
    guard dictionary.vm == .global else { throw Error.invalidAccess }
    try dictionary.access.check(.write)

    for entry in Self.requiredProcedures {
      try validateProcedure(dictionary.object(forKey: entry))
    }
    if let instanceType = try dictionary.object(forKeyIfExists: "InstanceType") {
      _ = try instanceType.value(as: NameValue.self)
    }
    if let fileName = try dictionary.object(forKeyIfExists: "ResourceFileName") {
      try validateProcedure(fileName)
    }
    try dictionary.updateObject(.literalName(categoryName.value), forKey: "Category")
  }

  private func validateProcedure(_ object: Object) throws {
    guard object.kind == .executable,
          object.value is any OperatorValue
            || object.value is ArrayValue
            || object.value is PackedArrayValue
    else {
      throw Error.typeCheck
    }
  }
}
