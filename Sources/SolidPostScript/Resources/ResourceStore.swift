import Foundation

struct ResourceEntry: Sendable {
  enum Origin: Int32, Sendable {
    case explicit = 0
    case automatic = 1
  }

  let id: UUID
  let instance: Object
  var origin: Origin
  var size: Int32

  init(id: UUID = UUID(), instance: Object, origin: Origin, size: Int32) {
    self.id = id
    self.instance = instance
    self.origin = origin
    self.size = size
  }
}

struct GlobalResourceMutation: Sendable {
  let key: Object
  let category: Object
  let previous: ResourceEntry?
  let replacementID: UUID?
}

struct RemovedResourceEntry: Sendable {
  let key: Object
  let category: Object
  let entry: ResourceEntry
}

struct ResourceStore: Sendable {
  private var categories: [Object: [Object: ResourceEntry]] = [:]

  func entry(for key: Object, in category: Object) throws -> ResourceEntry? {
    categories[try canonicalResourceKey(category)]?[try canonicalResourceKey(key)]
  }

  func entries(in category: Object) throws -> [Object: ResourceEntry] {
    categories[try canonicalResourceKey(category)] ?? [:]
  }

  @discardableResult
  mutating func define(_ entry: ResourceEntry, for key: Object, in category: Object) throws -> ResourceEntry? {
    let category = try canonicalResourceKey(category)
    return categories[category, default: [:]].updateValue(entry, forKey: try canonicalResourceKey(key))
  }

  @discardableResult
  mutating func remove(_ key: Object, from category: Object) throws -> ResourceEntry? {
    categories[try canonicalResourceKey(category)]?.removeValue(forKey: try canonicalResourceKey(key))
  }

  mutating func removeAutomaticEntries() -> [RemovedResourceEntry] {
    var removed: [RemovedResourceEntry] = []
    for category in Array(categories.keys) {
      guard let entries = categories[category] else { continue }
      for (key, entry) in entries where entry.origin == .automatic {
        removed.append(RemovedResourceEntry(key: key, category: category, entry: entry))
      }
      categories[category]?.filterValues { $0.origin != .automatic }
      if categories[category]?.isEmpty == true {
        categories.removeValue(forKey: category)
      }
    }
    return removed
  }

  var objects: [Object] {
    categories.flatMap { category, entries in
      [category] + entries.flatMap { [$0.key, $0.value.instance] }
    }
  }
}

func canonicalResourceKey(_ key: Object) throws -> Object {
  if let string = key.value as? StringValue {
    return .literalName(try string.readableString)
  }
  return key
}

private extension Dictionary {
  mutating func filterValues(_ isIncluded: (Value) throws -> Bool) rethrows {
    self = try filter { try isIncluded($0.value) }
  }
}
