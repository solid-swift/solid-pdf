//
//  ResourceOperators.swift
//
//
//  Created by Kevin Wooten on 7/8/24.
//

import Foundation

extension Operators {

  static let resourceOperators: [OperatorValue] = [
    ResourceOperator("DefineResource", "defineresource"),
    ResourceOperator("UndefineResource", "undefineresource"),
    ResourceOperator("FindResource", "findresource"),
    ResourceOperator("ResourceStatus", "resourcestatus"),
    ResourceOperator("ResourceForAll", "resourceforall", isolated: false),
  ]

  private static let categoriesDictName: Object = "@Internal.Resources"

  /// Implements the PostScript resource operator operator.
  public struct ResourceOperator: OperatorValue, Hashable {

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []
    /// The ``implementationKey`` value.
    public let implementationKey: Object
    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``isolated`` value.
    public let isolated: Bool

    /// Creates an instance.
    public init(_ implementationKey: Object, _ systemDictionaryNames: Object..., isolated: Bool = true) {
      self.implementationKey = implementationKey
      self.systemDictionaryNames = systemDictionaryNames
      self.isolated = isolated
    }

    static func resourceCategories(for context: isolated Context, vmOverride: VM? = nil) throws -> DictionaryValue {

      let vm = vmOverride ?? context.allocationMode

      let allocDict =
        if vm == .global {
          try context.dictionaries.globalDictionary()
        } else {
          try context.dictionaries.userDictionary()
        }

      guard let catDict = try allocDict.objectValue(forKeyIfExists: categoriesDictName, as: DictionaryValue.self) else {
        if vm == .local,
           let systemCategories = try context.dictionaries.systemDictionary()
            .objectValue(forKeyIfExists: categoriesDictName, as: DictionaryValue.self)
        {
          return systemCategories
        }
        try context.preflightAllocation(bytes: 32, vm: vm)
        let catDict = try DictionaryValue(value: [:], access: .unlimited, vm: vm)
        try context.preflightDictionaryGrowth(allocDict, key: categoriesDictName)
        try allocDict.updateObject(.init(value: catDict, kind: .literal), forKey: categoriesDictName)
        return catDict
      }
      return catDict
    }

    static func resources(for context: isolated Context, category key: Object, vmOveride: VM? = nil) throws
      -> DictionaryValue
    {
      let vm = vmOveride ?? context.allocationMode
      let catDict = try resourceCategories(for: context, vmOverride: vmOveride)

      if let resDict: DictionaryValue = try catDict.objectValue(forKeyIfExists: key) {
        return resDict
      }

      try context.preflightAllocation(bytes: 32, vm: vm)
      let resDict = try DictionaryValue(value: [:], access: .unlimited, vm: vm)
      try context.preflightDictionaryGrowth(catDict, key: key)
      try catDict.updateObject(.init(value: resDict, kind: .literal), forKey: key)
      return resDict
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (categoryKey) = try context.operands.pop()

      let resourceCategories = try Self.resourceCategories(for: context)

      let category = try resourceCategories.object(forKey: categoryKey)
      context.operands.push(category)

      try Begin.instance.execute(context: context)

      let result: Bool
      do {

        let implementationProc = try category.value(as: DictionaryValue.self).object(forKey: implementationKey)

        if let implementation = implementationProc.value as? any OperatorValue {
          try implementation.execute(context: context)
          result = true
        } else if isolated {
          result = try context.executeIsolated(proc: implementationProc)
        } else {
          result = try context.execute(proc: implementationProc)
        }

        try End.instance.execute(context: context)
      } catch {

        if isolated {
          try End.instance.execute(context: context)
        }

        throw error
      }

      if !result {
        throw Error.control(.exit)
      }
    }
  }

  /// Implements the PostScript resource operator implementation operator.
  public protocol ResourceOperatorImplementation: OperatorValue {

    var `extension`: (any ResourceCategoryExtension)? { get }
  }

  /// A PostScript resource category extension.
  public protocol ResourceCategoryExtension: Hashable, Sendable {

    func execute(context: isolated Context, instances: some Collection<Object>) throws
  }

  /// Performs the ``resourceCategoryImplementationNames`` operation.
  public static func resourceCategoryImplementationNames(_ name: String) -> [Object] {
    [.literalName("@Internal.ResourceCategory." + name)]
  }

  /// A PostScript define resource.
  public struct DefineResource: ResourceOperatorImplementation {

    /// The ``default`` value.
    public static var `default`: Object { .init(value: Self(), kind: .executable) }

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []

    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``extension`` value.
    public var `extension`: (any ResourceCategoryExtension)?

    /// Creates an instance.
    public init(
      systemDictionaryNames: [Object] = resourceCategoryImplementationNames("DefineResource"),
      extension: (any ResourceCategoryExtension)? = nil
    ) {
      self.systemDictionaryNames = systemDictionaryNames
      self.extension = `extension`
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (instance, key) = try context.operands.pop2()
      let categoryKey = try context.dictionaries.object(forKey: "Category")

      if let instanceType = try context.dictionaries.objectValue(forKeyIfExists: "InstanceType", as: NameValue.self),
        instance.type != ObjectType(instanceType.value)
      {
        throw Error.typeCheck
      }

      try self.extension?.execute(context: context, instances: [instance])

      let resources = try ResourceOperator.resources(for: context, category: categoryKey)

      try context.preflightDictionaryGrowth(resources, key: key)
      try resources.updateObject(instance, forKey: key)

      if context.allocationMode == .global {
        // Remove any local definition of instance
        _ = try context.dictionaries.userDictionary()
          .objectValue(forKeyIfExists: categoriesDictName, as: DictionaryValue.self)?
          .objectValue(forKeyIfExists: categoryKey, as: DictionaryValue.self)?
          .removeObject(forKey: key)
      }

      context.operands.push(instance)
    }
  }

  /// A PostScript find resource.
  public struct FindResource: ResourceOperatorImplementation {

    /// The ``default`` value.
    public static var `default`: Object { .init(value: Self(), kind: .executable) }

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []

    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``extension`` value.
    public var `extension`: (any ResourceCategoryExtension)?

    /// Creates an instance.
    public init(
      systemDictionaryNames: [Object] = resourceCategoryImplementationNames("FindResource"),
      extension: (any ResourceCategoryExtension)? = nil
    ) {
      self.systemDictionaryNames = systemDictionaryNames
      self.extension = `extension`
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")

      let resources = try ResourceOperator.resources(for: context, category: categoryKey)

      if let existingInstance = try resources.object(forKeyIfExists: key) {

        context.operands.push(existingInstance)
      } else {

        let defineProc = try context.dictionaries.object(forKey: "DefineResource")

        let newInstance = try Resources.loadInstance(forKey: key, in: categoryKey, context: context)

        try self.extension?.execute(context: context, instances: [newInstance])

        if try !context.execute(proc: defineProc, ops: [newInstance, key]) {
          throw Error.control(.exit)
        }
      }
    }
  }

  /// An PostScript undefine resource.
  public struct UndefineResource: ResourceOperatorImplementation {

    /// The ``default`` value.
    public static var `default`: Object { .init(value: Self(), kind: .executable) }

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []

    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``extension`` value.
    public var `extension`: (any ResourceCategoryExtension)?

    /// Creates an instance.
    public init(
      systemDictionaryNames: [Object] = resourceCategoryImplementationNames("UndefineResource"),
      extension: (any ResourceCategoryExtension)? = nil
    ) {
      self.systemDictionaryNames = systemDictionaryNames
      self.extension = `extension`
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")

      let instances: [Object?]

      if context.allocationMode == .local {

        let instance = try ResourceOperator.resources(for: context, category: categoryKey)
          .removeObject(forKey: key)

        instances = [instance]
      } else {

        let localInstance =
          try ResourceOperator.resources(for: context, category: categoryKey, vmOveride: .local)
          .removeObject(forKey: key) ?? .null

        let globalInstance =
          try ResourceOperator.resources(for: context, category: categoryKey)
          .removeObject(forKey: key) ?? .null

        instances = [localInstance, globalInstance]
      }

      try self.extension?.execute(context: context, instances: instances.compacted())
    }
  }

  /// A PostScript resource status.
  public struct ResourceStatus: ResourceOperatorImplementation {

    /// The ``default`` value.
    public static var `default`: Object { .init(value: Self(), kind: .executable) }

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []

    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``extension`` value.
    public var `extension`: (any ResourceCategoryExtension)?

    /// Creates an instance.
    public init(
      systemDictionaryNames: [Object] = resourceCategoryImplementationNames("ResourceStatus"),
      extension: (any ResourceCategoryExtension)? = nil
    ) {
      self.systemDictionaryNames = systemDictionaryNames
      self.extension = `extension`
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")

      let instance: Object? =
        if context.allocationMode == .local {

          try ResourceOperator.resources(for: context, category: categoryKey)
            .object(forKeyIfExists: key)
            ?? ResourceOperator.resources(for: context, category: categoryKey, vmOveride: .global)
            .object(forKeyIfExists: key)
        } else {

          try ResourceOperator.resources(for: context, category: categoryKey, vmOveride: .global)
            .object(forKeyIfExists: key)
        }

      if let instance {

        if let ext = self.extension {

          try ext.execute(context: context, instances: [instance])
        }

        let resourceCategory = try Resources.loadCategory(forKey: categoryKey)

        let size = try resourceCategory.sizeOfResource(instance)

        context.operands.push(
          .boolean(true),
          try NumericSemantics.integer(validating: size),
          .integer(0)
        )
      } else {

        let resourceCategory = try Resources.loadCategory(forKey: categoryKey)

        if let status = try resourceCategory.statusOfResource(forKey: key) {

          context.operands.push(
            .boolean(true),
            try NumericSemantics.integer(validating: status.size),
            .integer(status.isLoaded ? 1 : 2)
          )
        } else {

          context.operands.push(.boolean(false))
        }
      }
    }
  }

  /// A PostScript resource for all.
  public struct ResourceForAll: ResourceOperatorImplementation {

    /// The ``default`` value.
    public static var `default`: Object { .init(value: Self(), kind: .executable) }

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = []

    /// The names that register this operator in the system dictionary.
    public let systemDictionaryNames: [Object]
    /// The ``extension`` value.
    public var `extension`: (any ResourceCategoryExtension)?

    /// Creates an instance.
    public init(
      systemDictionaryNames: [Object] = resourceCategoryImplementationNames("ResourceForAll"),
      extension: (any ResourceCategoryExtension)? = nil
    ) {
      self.systemDictionaryNames = systemDictionaryNames
      self.extension = `extension`
    }

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (scratchObj, proc, templateObj) = try context.operands.pop3()
      let categoryKey = try context.dictionaries.object(forKey: "Category")
      let scratch = try scratchObj.value(as: StringValue.self)
      let template = try templateObj.value(as: NameStringConvertible.self).nameString

      var resourceKeys: [Object] = []

      if context.allocationMode == .local {

        resourceKeys.append(
          contentsOf: try ResourceOperator.resources(for: context, category: categoryKey).keys
            .filter { !$0.isResourceImplementationKey }
        )
      }

      resourceKeys.append(
        contentsOf:
          try ResourceOperator
          .resources(for: context, category: categoryKey, vmOveride: .global).keys
          .filter { !$0.isResourceImplementationKey }
      )

      let category = try Resources.loadCategory(forKey: categoryKey)
      resourceKeys.append(contentsOf: try category.enumerateResources(matching: template))

      guard let regex = template.asTemplateRegex else { return }
      var seen = Set<Object>()
      resourceKeys = try resourceKeys.filter { key in
        guard seen.insert(key).inserted else { return false }
        let name = try key.value(as: NameStringConvertible.self).nameString
        return (try? regex.wholeMatch(in: name)) != nil
      }

      for resourceKey in resourceKeys {

        let procArg: Object

        if categoryKey == "IODevice", let nameKey = resourceKey.value as? NameValue {
          let characters = Data(nameKey.value.utf8)
          try scratch.updateCharacters(characters, startingAt: 0)
          procArg = try .string(sharing: scratch, subRange: 0..<UInt(characters.count), kind: .literal)
        } else if let stringKey = resourceKey.value as? StringValue {

          let characters = try stringKey.characters(in: stringKey.range)
          try scratch.updateCharacters(characters, startingAt: 0)

          procArg = try .string(sharing: scratch, subRange: 0..<UInt(characters.count), kind: .literal)
        } else {

          procArg = resourceKey
        }

        if try !context.execute(proc: proc, ops: [procArg]) {
          throw Error.control(.exit)
        }
      }
    }
  }
}

private extension Object {

  var isResourceImplementationKey: Bool {
    guard let name = value as? NameValue else { return false }
    return [
      "Category",
      "DefineResource",
      "UndefineResource",
      "FindResource",
      "ResourceStatus",
      "ResourceForAll",
      "InstanceType",
      "FileName",
    ].contains(name.value)
  }

}

extension Operators.ResourceOperatorImplementation {

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {

    func compareExts<E>(_ e1: E, _ e2: any Operators.ResourceCategoryExtension) -> Bool
    where E: Operators.ResourceCategoryExtension {

      guard let e2 = e2 as? E else {
        return false
      }
      return e1 == e2
    }

    guard let other = other as? Self else {
      return false
    }

    switch (self.extension, other.extension) {
    case (nil, nil):
      return true
    case (.some(let selfExt), .some(let otherExt)):
      return compareExts(selfExt, otherExt)
    default:
      return false
    }
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    guard let ext = self.extension else {
      return
    }
    hasher.combine(ext)
  }

}
