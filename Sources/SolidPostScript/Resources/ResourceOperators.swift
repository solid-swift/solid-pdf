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

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let savedOperands = context.operands
      let savedDictionaries = context.dictionaries

      do {
        let categoryKey = try context.operands.pop()
        let category = try await ResourceRuntime.categoryDictionary(categoryKey, context: context)
        context.operands.push(category)

        try await Begin.instance.execute(context: context)

        let implementationProc = try category.value(as: DictionaryValue.self).object(forKey: implementationKey)

        let executeImplementation = {
          if let implementation = implementationProc.value as? any OperatorValue {
            try await implementation.execute(context: context)
          } else if isolated {
            try await context.executeIsolated(proc: implementationProc)
          } else {
            try await context.execute(proc: implementationProc)
          }
        }

        if systemDictionaryNames.contains(where: { ($0.value as? NameValue)?.value == "resourceforall" }) {
          try await context.executeLoop(named: "resourceforall", executeImplementation)
        } else {
          try await executeImplementation()
        }

        try await End.instance.execute(context: context)
      } catch {
        if isolated {
          context.operands = savedOperands
          context.dictionaries = savedDictionaries
        }
        throw error
      }
    }
  }

  /// Implements the PostScript resource operator implementation operator.
  public protocol ResourceOperatorImplementation: OperatorValue {

    var `extension`: (any ResourceCategoryExtension)? { get }
  }

  /// A PostScript resource category extension.
  public protocol ResourceCategoryExtension: Hashable, Sendable {

    /// Compatibility callback used by extensions written before lifecycle-specific hooks existed.
    func execute(context: isolated Context, instances: some Collection<Object>) throws
    /// Validates an instance before an explicit definition is committed.
    func validateDefinition(key: Object, instance: Object, context: isolated Context) throws
    /// Validates an instance supplied by a resource provider or external file.
    func validateLoaded(key: Object, instance: Object, context: isolated Context) throws
    /// Performs category-specific work after a definition is committed.
    func didDefine(key: Object, instance: Object, context: isolated Context) throws
    /// Performs category-specific work before a definition is removed.
    func willUndefine(key: Object, instance: Object, context: isolated Context) throws
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
    public func execute(context: isolated Context) async throws {

      let (instance, key) = try context.operands.pop2()
      let categoryKey = try context.dictionaries.object(forKey: "Category")
      context.operands.push(
        try await ResourceRuntime.define(
          instance,
          for: key,
          in: categoryKey,
          origin: .explicit,
          implementationExtension: self.extension,
          context: context
        )
      )
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
    public func execute(context: isolated Context) async throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")
      context.operands.push(
        try await ResourceRuntime.find(
          key,
          in: categoryKey,
          implementationExtension: self.extension,
          context: context
        )
      )
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
    public func execute(context: isolated Context) async throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")
      try await ResourceRuntime.remove(
        key,
        from: categoryKey,
        implementationExtension: self.extension,
        context: context
      )
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
    public func execute(context: isolated Context) async throws {

      let key = try context.operands.pop()
      let categoryKey = try context.dictionaries.object(forKey: "Category")
      if let entry = try ResourceRuntime.visibleEntry(for: key, in: categoryKey, context: context) {
        try self.extension?.execute(context: context, instances: [entry.instance])
        let provider = try ResourceRuntime.provider(categoryKey, context: context)
        let size = entry.size >= 0 ? Int(entry.size) : try provider?.sizeOfResource(entry.instance) ?? -1
        context.operands.push(
          .boolean(true),
          try NumericSemantics.integer(validating: size),
          .integer(entry.origin.rawValue)
        )
      } else if let provider = try ResourceRuntime.provider(categoryKey, context: context),
                let status = try provider.statusOfResource(forKey: key)
      {
          context.operands.push(
            .boolean(true),
            try NumericSemantics.integer(validating: status.size),
            .integer(status.isLoaded ? 0 : 2)
          )
      } else if let availability = try await ResourceRuntime.externalAvailability(
        for: key,
        in: categoryKey,
        context: context
      ) {
        context.operands.push(
          .boolean(true),
          .integer(availability.size),
          .integer(2)
        )
      } else {
        context.operands.push(.boolean(false))
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
    public func execute(context: isolated Context) async throws {

      var categoryDictionaryActive = true
      var activeCategoryKey: Object?
      do {
        let (scratchObj, proc, templateObj) = try context.operands.pop3()
        let categoryKey = try context.dictionaries.object(forKey: "Category")
        activeCategoryKey = categoryKey
        let scratch = try scratchObj.value(as: StringValue.self)
        let templateString = try templateObj.value(as: StringValue.self)
        try templateString.access.check(.read)
        try scratch.access.check(.write)
        try proc.checkProcedure()
        let template = templateString.nameString

        var resourceKeys: [Object] = []
        let stored = try ResourceRuntime.storedEntries(in: categoryKey, context: context)
        resourceKeys.append(contentsOf: stored.filter { $0.entry.origin == .explicit }.map(\.key))

        var providerAvailable: [Object] = []
        if let provider = try ResourceRuntime.provider(categoryKey, context: context) {
          for key in try provider.enumerateResources(matching: template) {
            if try provider.statusOfResource(forKey: key)?.isLoaded == true {
              resourceKeys.append(key)
            } else {
              providerAvailable.append(key)
            }
          }
        }
        resourceKeys.append(contentsOf: stored.filter { $0.entry.origin == .automatic }.map(\.key))
        resourceKeys.append(contentsOf: providerAvailable)
        resourceKeys.append(
          contentsOf: try await ResourceFiles.externalKeys(
            in: categoryKey,
            matching: template,
            context: context
          )
        )

        guard let regex = template.asTemplateRegex else { return }
        var seen = Set<Object>()
        resourceKeys = try resourceKeys.filter { key in
          guard seen.insert(try canonicalResourceKey(key)).inserted else { return false }
          guard let name = key.value as? NameStringConvertible else { return template == "*" }
          if let string = key.value as? StringValue { try string.access.check(.read) }
          return (try? regex.wholeMatch(in: name.nameString)) != nil
        }

        try await End.instance.execute(context: context)
        categoryDictionaryActive = false
        for resourceKey in resourceKeys {

          let procArg: Object

          if let nameString = resourceKey.value as? NameStringConvertible {
            let characters = Data(nameString.nameString.utf8)
            guard characters.count <= scratch.count else { throw Error.rangeCheck }
            try scratch.updateCharacters(characters, startingAt: 0)
            procArg = try .string(sharing: scratch, subRange: 0..<UInt(characters.count), kind: .literal)
          } else {
            procArg = resourceKey
          }

          try await context.execute(proc: proc, ops: [procArg])
        }
        try context.dictionaries.push(try await ResourceRuntime.categoryDictionary(categoryKey, context: context))
        categoryDictionaryActive = true
      } catch let transfer as LoopExitTransfer {
        if !categoryDictionaryActive, let categoryKey = activeCategoryKey {
          try context.dictionaries.push(try await ResourceRuntime.categoryDictionary(categoryKey, context: context))
          categoryDictionaryActive = true
        }
        throw transfer
      } catch {
        if categoryDictionaryActive {
          try? await End.instance.execute(context: context)
        }
        throw error
      }
    }
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

extension Operators.ResourceCategoryExtension {
  /// Deprecated compatibility hook for extensions created before lifecycle-specific callbacks existed.
  public func execute(context: isolated Context, instances: some Collection<Object>) throws {}

  /// Validates an explicitly defined instance.
  public func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    try execute(context: context, instances: [instance])
  }

  /// Validates an instance supplied by an external provider.
  public func validateLoaded(key: Object, instance: Object, context: isolated Context) throws {
    try execute(context: context, instances: [instance])
  }

  /// Performs category-specific work after an instance is committed.
  public func didDefine(key: Object, instance: Object, context: isolated Context) throws {}

  /// Performs category-specific work before an instance is removed.
  public func willUndefine(key: Object, instance: Object, context: isolated Context) throws {}
}
