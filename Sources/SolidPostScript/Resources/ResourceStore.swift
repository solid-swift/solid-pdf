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

  mutating func removeAutomaticEntries() {
    for category in Array(categories.keys) {
      categories[category]?.filterValues { $0.origin != .automatic }
      if categories[category]?.isEmpty == true {
        categories.removeValue(forKey: category)
      }
    }
  }

  var objects: [Object] {
    categories.flatMap { category, entries in
      [category] + entries.flatMap { [$0.key, $0.value.instance] }
    }
  }
}

func canonicalResourceKey(_ key: Object) throws -> Object {
  if let string = key.value as? StringValue {
    try string.access.check(.read)
    return .literalName(string.string)
  }
  return key
}

private extension Dictionary {
  mutating func filterValues(_ isIncluded: (Value) throws -> Bool) rethrows {
    self = try filter { try isIncluded($0.value) }
  }
}
