//
//  NameTable.swift
//

import Foundation
import Synchronization

final class NameTable: Sendable {

  private struct Entry: Sendable {
    let name: String
    let allocation: VMAllocation
  }

  private let globalVM: VMAllocationSpace
  private let entries = Mutex<[String: Entry]>([:])

  init(globalVM: VMAllocationSpace) {
    self.globalVM = globalVM
  }

  func intern(_ name: String) -> String {
    entries.withLock { entries in
      if let entry = entries[name] {
        return entry.name
      }

      let byteCount = name.data(using: .isoLatin1)?.count ?? name.utf8.count
      let entry = Entry(
        name: name,
        allocation: globalVM.allocatePermanent(bytes: byteCount.saturatingAdd(24))
      )
      entries[name] = entry
      return entry.name
    }
  }

  func intern(_ objects: some Sequence<Object>) throws {
    var visited = Set<ObjectIdentifier>()

    func visit(_ object: Object) throws {
      if let name = object.value as? NameValue {
        _ = intern(name.value)
        return
      }
      guard let composite = object.value as? VMAllocatedCompositeValue else { return }
      guard visited.insert(composite.allocation.identity).inserted else { return }

      switch object.value {
      case let dictionary as DictionaryValue:
        try dictionary.forEachUnchecked { key, value in
          try visit(key)
          try visit(value)
        }
      case let collection as any SharedBackingArrayValue:
        try collection.forEachBackingUnchecked(visit)
      case let collection as any CollectionValue:
        try collection.forEachUnchecked(visit)
      default:
        break
      }
    }

    for object in objects {
      try visit(object)
    }
  }
}

enum NameInterningContext {
  @TaskLocal static var table: NameTable?
}

private extension Int {
  func saturatingAdd(_ other: Int) -> Int {
    let (value, overflow) = addingReportingOverflow(other)
    return overflow ? .max : value
  }
}
