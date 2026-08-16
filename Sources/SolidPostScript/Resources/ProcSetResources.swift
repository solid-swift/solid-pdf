//
//  ProcSetResources.swift
//
//
//  Created by Kevin Wooten on 7/9/24.
//

import Foundation
import Synchronization
import SolidCore

/// A PostScript resource category that manages procedure sets.
public final class ProcSetResources: ResourceCategory {

  /// The ``procSets`` value.
  public let procSets: [any ProcSet]
  private let loadedProcSets = Mutex<[Object: Weak<DictionaryValue.Shared>]>([:])

  /// Creates an instance.
  public init(procSets: [any ProcSet] = []) {
    self.procSets = procSets
  }

  /// The ``dictionary`` value.
  public var dictionary: ResourceCategoryDictionary {
    .init(category: "ProcSet", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  /// Performs the ``loadResource`` operation.
  public func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {

    guard
      let keyString = key.value as? NameStringConvertible,
      let procSet = procSets.first(where: { $0.name == keyString.nameString })
    else {
      throw Error.undefinedResource
    }

    let source = procSet.load()
    let file = DataFile(data: source.data(using: .isoLatin1).neverNil(), mode: .read)
    try await context.pushAndRun(source: .file(file, access: .readOnly, vm: .local, kind: .executable))

    return try context.dictionaries.object(forKey: key)
  }

  /// Performs the ``sizeOfResource`` operation.
  public func sizeOfResource(_ instance: Object) throws -> Int {
    return -1
  }

  /// Performs the ``statusOfResource`` operation.
  public func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {

    guard
      let keyString = key.value as? NameStringConvertible,
      procSets.contains(where: { $0.name == keyString.nameString })
    else {
      return nil
    }

    let isLoaded = loadedProcSets.withLock { $0[key] != nil }

    return (isLoaded, -1)
  }

  /// Performs the ``enumerateResources`` operation.
  public func enumerateResources(matching template: String) throws -> [Object] {

    guard let template = template.asTemplateRegex else {
      return []
    }

    var results: [Object] = []

    for procSet in procSets {
      let match = try? template.wholeMatch(in: procSet.name)
      if match != nil {
        results.append(.string(procSet.name, access: .readOnly, vm: .local, kind: .literal))
      }
    }

    return results
  }

}

struct Weak<Value: AnyObject> {
  weak var value: Value?
}
