import Foundation

extension Operators {
  struct ResourceFileName: OperatorValue, Hashable {
    static let `default`: Object = .init(value: Self(), kind: .executable)
    static let systemDictionaryNames: [Object] = []

    func execute(context: isolated Context) async throws {
      let (scratchObject, key) = try context.operands.pop2()
      let category = try context.dictionaries.object(forKey: "Category")
      let scratch = try scratchObject.value(as: StringValue.self)
      try scratch.access.check(.write)
      guard let path = try ResourceFiles.defaultPath(for: key, in: category, context: context) else {
        throw Error.undefinedResource
      }
      let bytes = try LanguageLimits.postScriptBytes(path)
      guard bytes.count <= scratch.count else { throw Error.rangeCheck }
      try scratch.updateCharacters(bytes, startingAt: 0)
      context.operands.push(try .string(sharing: scratch, subRange: 0..<UInt(bytes.count), kind: .literal))
    }
  }
}

enum ResourceFiles {
  struct Availability {
    let path: String
    let size: Int32
  }

  static func availability(
    for key: Object,
    in category: Object,
    context: isolated Context
  ) async throws -> Availability? {
    guard let path = try await fileName(for: key, in: category, context: context),
          try context.fileDevices.resourceFileMetadata(name: path) != nil
    else {
      return nil
    }
    return Availability(path: path, size: try vmUsage(at: path, context: context))
  }

  static func externalKeys(
    in category: Object,
    matching template: String,
    context: isolated Context
  ) async throws -> [Object] {
    let implementation = try await ResourceRuntime.categoryDictionary(category, context: context)
      .value(as: DictionaryValue.self)
    guard let fileName = try implementation.object(forKeyIfExists: "ResourceFileName"),
          fileName.value is Operators.ResourceFileName,
          let directory = try defaultDirectory(for: category, context: context)
    else {
      return []
    }
    guard let regex = template.asTemplateRegex else { return [] }
    return try context.fileDevices.resourceFileNames(in: directory).compactMap { name in
      guard (try? LanguageLimits.validateName(name)) != nil else { return nil }
      guard (try? regex.wholeMatch(in: name)) != nil else { return nil }
      return .literalName(name)
    }
  }

  static func load(_ availability: Availability, context: isolated Context) async throws {
    let file: any File
    do {
      file = try context.fileDevices.open(name: availability.path, mode: "r")
    } catch Error.undefinedFilename {
      throw Error.undefinedResource
    }
    let source: Object = .file(file, access: .readOnly, vm: .global, kind: .executable)
    try await context.execute(proc: source)
  }

  static func defaultPath(
    for key: Object,
    in category: Object,
    context: isolated Context
  ) throws -> String? {
    guard let key = try resourceName(key) else { return nil }
    let categoryName = try category.value(as: NameValue.self).value
    if categoryName == "Font" {
      guard let directory = context.environment.systemString("FontResourceDir"), directory != "%null" else {
        return nil
      }
      return directory + key
    }
    guard let directory = context.environment.systemString("GenericResourceDir"), directory != "%null",
          let separator = context.environment.systemString("GenericResourcePathSep")
    else {
      return nil
    }
    return directory + categoryName + separator + key
  }

  private static func defaultDirectory(for category: Object, context: isolated Context) throws -> String? {
    let categoryName = try category.value(as: NameValue.self).value
    if categoryName == "Font" {
      guard let directory = context.environment.systemString("FontResourceDir"), directory != "%null" else {
        return nil
      }
      return directory
    }
    guard let directory = context.environment.systemString("GenericResourceDir"), directory != "%null",
          let separator = context.environment.systemString("GenericResourcePathSep")
    else {
      return nil
    }
    return directory + categoryName + separator
  }

  private static func fileName(
    for key: Object,
    in category: Object,
    context: isolated Context
  ) async throws -> String? {
    let implementation = try await ResourceRuntime.categoryDictionary(category, context: context)
      .value(as: DictionaryValue.self)
    guard let procedure = try implementation.object(forKeyIfExists: "ResourceFileName") else { return nil }
    if procedure.value is Operators.ResourceFileName {
      return try defaultPath(for: key, in: category, context: context)
    }

    let savedOperands = context.operands
    defer { context.operands = savedOperands }
    let scratch = Object.string(Data(repeating: 0, count: 4096), access: .unlimited, vm: .local, kind: .literal)
    try await context.execute(proc: procedure, ops: [key, scratch])
    let result: StringValue = try context.operands.popAs()
    return try result.readableString
  }

  private static func resourceName(_ key: Object) throws -> String? {
    if let string = key.value as? StringValue {
      return try string.readableString
    }
    return (key.value as? NameValue)?.value
  }

  private static func vmUsage(at path: String, context: isolated Context) throws -> Int32 {
    let file = try context.fileDevices.open(name: path, mode: "r")
    defer { try? file.close() }
    let data = try file.read(max: 8192) ?? Data()
    guard let text = String(data: data, encoding: .isoLatin1) else { return -1 }
    for line in text.split(whereSeparator: \.isNewline) {
      if line == "%%EndComments" || !line.hasPrefix("%") { break }
      guard line.hasPrefix("%%VMusage:") else { continue }
      let values = line.dropFirst("%%VMusage:".count).split(whereSeparator: \.isWhitespace)
      guard values.count >= 2, let first = Int32(values[0]), let second = Int32(values[1]) else { return -1 }
      return max(first, second)
    }
    return -1
  }
}
