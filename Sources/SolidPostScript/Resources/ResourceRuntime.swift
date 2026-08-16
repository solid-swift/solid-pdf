import Foundation

enum ResourceRuntime {
  static let categoryCategory: Object = "Category"

  static func categoryDictionary(_ category: Object, context: isolated Context) throws -> Object {
    let category = try categoryName(category)
    if let entry = try context.environment.globalResource(for: category, in: categoryCategory) {
      return entry.instance
    }
    guard category != categoryCategory else { throw Error.undefined }
    do {
      return try find(category, in: categoryCategory, context: context)
    } catch Error.undefinedResource {
      throw Error.undefined
    }
  }

  static func provider(_ category: Object, context: isolated Context) throws -> (any ResourceCategory)? {
    try context.environment.resourceCategory(for: category)
  }

  static func visibleEntry(
    for key: Object,
    in category: Object,
    context: isolated Context
  ) throws -> ResourceEntry? {
    let category = try categoryName(category)
    if context.allocationMode == .local,
       let local = try context.localResources.entry(for: key, in: category)
    {
      return local
    }
    return try context.environment.globalResource(for: key, in: category)
  }

  static func define(
    _ instance: Object,
    for key: Object,
    in category: Object,
    origin: ResourceEntry.Origin,
    size: Int32 = -1,
    implementationExtension: (any Operators.ResourceCategoryExtension)? = nil,
    context: isolated Context
  ) throws -> Object {
    let category = try categoryName(category)
    let canonicalKey = try canonicalResourceKey(key)
    let categoryDictionary = try categoryDictionary(category, context: context)
    let implementation = try categoryDictionary.value(as: DictionaryValue.self)

    try validateInstanceType(instance, implementation: implementation)

    let categoryExtension = try provider(category, context: context)?.resourceExtension
    try categoryExtension?.validateDefinition(key: canonicalKey, instance: instance, context: context)
    if let implementationExtension,
       categoryExtension.map({ !extensionsEqual($0, implementationExtension) }) ?? true
    {
      try implementationExtension.validateDefinition(key: canonicalKey, instance: instance, context: context)
    }

    try canonicalKey.checkStorage(in: context.allocationMode)
    try instance.checkStorage(in: context.allocationMode)
    let instance = try restrictedInstance(instance)
    try context.preflightAllocation(bytes: 32, vm: context.allocationMode)

    let entry = ResourceEntry(instance: instance, origin: origin, size: size)
    let definitionVM = context.allocationMode
    let previousLocal = try context.localResources.entry(for: canonicalKey, in: category)
    let previousGlobal = try context.environment.globalResource(for: canonicalKey, in: category)
    if definitionVM == .local {
      try context.localResources.define(entry, for: canonicalKey, in: category)
    } else {
      _ = try context.localResources.remove(canonicalKey, from: category)
      try context.environment.defineGlobalResource(entry, for: canonicalKey, in: category)
    }

    do {
      try categoryExtension?.didDefine(key: canonicalKey, instance: instance, context: context)
      if let implementationExtension,
         categoryExtension.map({ !extensionsEqual($0, implementationExtension) }) ?? true
      {
        try implementationExtension.didDefine(key: canonicalKey, instance: instance, context: context)
      }
    } catch {
      try restore(previousLocal, for: canonicalKey, in: category, store: &context.localResources)
      if definitionVM == .global {
        if let previousGlobal {
          try context.environment.defineGlobalResource(previousGlobal, for: canonicalKey, in: category)
        } else {
          _ = try context.environment.removeGlobalResource(canonicalKey, from: category)
        }
      }
      throw error
    }
    if definitionVM == .global {
      context.recordGlobalResourceMutation(
        GlobalResourceMutation(
          key: canonicalKey,
          category: category,
          previous: previousGlobal,
          replacementID: entry.id
        )
      )
    }
    return instance
  }

  static func find(
    _ key: Object,
    in category: Object,
    implementationExtension: (any Operators.ResourceCategoryExtension)? = nil,
    context: isolated Context
  ) throws -> Object {
    let category = try categoryName(category)
    let implementation = try categoryDictionary(category, context: context).value(as: DictionaryValue.self)
    if let entry = try visibleEntry(for: key, in: category, context: context) {
      return entry.instance
    }

    if let provider = try provider(category, context: context),
       let availability = try provider.statusOfResource(forKey: key)
    {
      let instance = try provider.loadResource(forKey: key, in: context)
      try validateInstanceType(instance, implementation: implementation)
      try provider.resourceExtension?.validateLoaded(key: key, instance: instance, context: context)
      if let implementationExtension,
         provider.resourceExtension.map({ !extensionsEqual($0, implementationExtension) }) ?? true
      {
        try implementationExtension.validateLoaded(key: key, instance: instance, context: context)
      }

      if availability.isLoaded {
        return instance
      }

      let savedMode = context.allocationMode
      context.allocationMode = .global
      defer { context.allocationMode = savedMode }
      return try define(
        instance,
        for: key,
        in: category,
        origin: .automatic,
        size: Int32(clamping: availability.size),
        context: context
      )
    }
    if let loaded = try loadExternal(key, in: category, context: context) { return loaded }
    throw Error.undefinedResource
  }

  static func remove(
    _ key: Object,
    from category: Object,
    implementationExtension: (any Operators.ResourceCategoryExtension)? = nil,
    context: isolated Context
  ) throws {
    let category = try categoryName(category)
    _ = try categoryDictionary(category, context: context)
    let categoryExtension = try provider(category, context: context)?.resourceExtension

    if try visibleEntry(for: key, in: category, context: context) == nil,
       let provider = try provider(category, context: context),
       let availability = try provider.statusOfResource(forKey: key),
       availability.isLoaded
    {
      let instance = try provider.loadResource(forKey: key, in: context)
      try categoryExtension?.willUndefine(key: key, instance: instance, context: context)
      try implementationExtension?.willUndefine(key: key, instance: instance, context: context)
      return
    }

    var removed: [ResourceEntry] = []
    if context.allocationMode == .local {
      if let entry = try context.localResources.entry(for: key, in: category) {
        try categoryExtension?.willUndefine(key: key, instance: entry.instance, context: context)
        try implementationExtension?.willUndefine(key: key, instance: entry.instance, context: context)
        if let removedEntry = try context.localResources.remove(key, from: category) {
          removed.append(removedEntry)
        }
      }
    } else {
      if let entry = try context.localResources.entry(for: key, in: category) {
        try categoryExtension?.willUndefine(key: key, instance: entry.instance, context: context)
        try implementationExtension?.willUndefine(key: key, instance: entry.instance, context: context)
      }
      if let entry = try context.environment.globalResource(for: key, in: category) {
        try categoryExtension?.willUndefine(key: key, instance: entry.instance, context: context)
        try implementationExtension?.willUndefine(key: key, instance: entry.instance, context: context)
      }
      if let entry = try context.localResources.remove(key, from: category) { removed.append(entry) }
      if let entry = try context.environment.removeGlobalResource(key, from: category) {
        removed.append(entry)
        context.recordGlobalResourceMutation(
          GlobalResourceMutation(
            key: try canonicalResourceKey(key),
            category: category,
            previous: entry,
            replacementID: nil
          )
        )
      }
    }
    _ = removed
  }

  static func storedEntries(
    in category: Object,
    context: isolated Context
  ) throws -> [(key: Object, entry: ResourceEntry)] {
    let category = try categoryName(category)
    var results: [(Object, ResourceEntry)] = []
    var seen = Set<Object>()
    if context.allocationMode == .local {
      for pair in try context.localResources.entries(in: category) {
        seen.insert(pair.key)
        results.append(pair)
      }
    }
    for pair in try context.environment.globalResourceEntries(in: category) where seen.insert(pair.key).inserted {
      results.append(pair)
    }
    return results
  }

  static func reclaimAutomaticResources(context: isolated Context, includeGlobal: Bool) {
    context.localResources.removeAutomaticEntries()
    if includeGlobal {
      context.environment.reclaimAutomaticGlobalResources()
    }
  }

  static func externalAvailability(
    for key: Object,
    in category: Object,
    context: isolated Context
  ) throws -> ResourceFiles.Availability? {
    try ResourceFiles.availability(for: key, in: categoryName(category), context: context)
  }

  private static func loadExternal(
    _ key: Object,
    in category: Object,
    context: isolated Context
  ) throws -> Object? {
    guard let availability = try ResourceFiles.availability(
      for: key,
      in: category,
      context: context
    ) else {
      return nil
    }

    let category = try categoryName(category)
    let canonicalKey = try canonicalResourceKey(key)
    let savedMode = context.allocationMode
    let savedLocalResources = context.localResources
    let previousLocal = try context.localResources.entry(for: canonicalKey, in: category)
    let previousGlobal = try context.environment.globalResource(for: canonicalKey, in: category)
    context.resourceLoadTransactions.append([])
    context.allocationMode = .global
    do {
      try ResourceFiles.load(availability, context: context)
      let loaded: ResourceEntry?
      if let global = try context.environment.globalResource(for: canonicalKey, in: category),
         global.id != previousGlobal?.id
      {
        var entry = global
        entry.origin = .automatic
        entry.size = availability.size
        try context.environment.defineGlobalResource(entry, for: canonicalKey, in: category)
        loaded = entry
      } else if let local = try context.localResources.entry(for: canonicalKey, in: category),
                local.id != previousLocal?.id
      {
        let entry = ResourceEntry(instance: local.instance, origin: .automatic, size: availability.size)
        try context.localResources.define(entry, for: canonicalKey, in: category)
        loaded = entry
      } else {
        loaded = nil
      }
      guard let loaded else { throw Error.undefinedResource }
      try provider(category, context: context)?.resourceExtension?
        .validateLoaded(key: canonicalKey, instance: loaded.instance, context: context)
      context.allocationMode = savedMode
      if savedMode == .global,
         let composite = loaded.instance.value as? any CompositeValue,
         composite.vm == .local
      {
        throw Error.undefinedResource
      }
      _ = context.resourceLoadTransactions.removeLast()
      return loaded.instance
    } catch {
      let mutations = context.resourceLoadTransactions.removeLast()
      context.localResources = savedLocalResources
      try? context.environment.rollbackGlobalResourceMutations(mutations)
      context.allocationMode = savedMode
      throw error
    }
  }

  private static func categoryName(_ category: Object) throws -> Object {
    .literalName(try category.value(as: NameValue.self).value)
  }

  private static func restrictedInstance(_ instance: Object) throws -> Object {
    switch instance.value {
    case var value as ArrayValue where value.access == .unlimited:
      try value.setAccess(to: .readOnly)
      return Object(value: value, kind: instance.kind)
    case let value as DictionaryValue where value.access == .unlimited:
      try value.setAccess(to: .readOnly)
      return instance
    case var value as StringValue where value.access == .unlimited:
      try value.setAccess(to: .readOnly)
      return Object(value: value, kind: instance.kind)
    case var value as PackedArrayValue where value.access == .unlimited:
      try value.setAccess(to: .readOnly)
      return Object(value: value, kind: instance.kind)
    default:
      return instance
    }
  }

  private static func validateInstanceType(_ instance: Object, implementation: DictionaryValue) throws {
    if let instanceType = try implementation.objectValue(forKeyIfExists: "InstanceType", as: NameValue.self),
       instance.type != ObjectType(instanceType.value)
    {
      throw Error.typeCheck
    }
  }

  private static func restore(
    _ entry: ResourceEntry?,
    for key: Object,
    in category: Object,
    store: inout ResourceStore
  ) throws {
    if let entry {
      try store.define(entry, for: key, in: category)
    } else {
      _ = try store.remove(key, from: category)
    }
  }

  private static func extensionsEqual(
    _ lhs: any Operators.ResourceCategoryExtension,
    _ rhs: any Operators.ResourceCategoryExtension
  ) -> Bool {
    func compare<E: Operators.ResourceCategoryExtension>(_ lhs: E) -> Bool {
      guard let rhs = rhs as? E else { return false }
      return lhs == rhs
    }
    return compare(lhs)
  }
}
