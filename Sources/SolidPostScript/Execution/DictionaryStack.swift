//
//  DictionaryStack.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore

struct DictionaryStack {

  typealias Storage = Stack<Object>

  private var storage: Storage

  init(_ dictionaries: [Object] = []) {
    self.storage = Stack(dictionaries)
  }

  init(_ storage: Storage = .init()) {
    self.storage = storage
  }

  func objectValue<V>(forKey key: Object, as: V.Type = V.self) throws -> V? {

    return try object(forKey: key).value(as: V.self)
  }

  func object(forKey key: Object) throws -> Object {

    for dictionaryObj in storage {

      let dictionary = try dictionaryObj.value(as: DictionaryValue.self)

      if let object = try dictionary.object(forKeyIfExists: key) {
        return object
      }
    }

    throw Error.undefined
  }

  func objectValue<V>(forKeyIfExists key: Object, as: V.Type = V.self) throws -> V? {

    return try object(forKeyIfExists: key)?.source.value(as: V.self)
  }

  func object(forKeyIfExists key: Object) throws -> (source: Object, value: Object)? {

    for dictionaryObj in storage {

      let dictionary = try dictionaryObj.value(as: DictionaryValue.self)

      if let object = try dictionary.object(forKeyIfExists: key) {
        return (dictionaryObj, object)
      }
    }

    return nil
  }

  func updateObject(_ object: Object, forKey key: Object) throws -> Object? {

    for dictionaryObj in storage {

      let dictionary = try dictionaryObj.value(as: DictionaryValue.self)

      if try dictionary.object(forKeyIfExists: key) != nil {
        return try dictionary.updateObject(object, forKey: key)
      }
    }

    return try currentDictionary().updateObject(object, forKey: key)
  }

  func removeObject(forKey key: Object) throws -> Object? {

    for dictionaryObj in storage {

      let dictionary = try dictionaryObj.value(as: DictionaryValue.self)

      if let object = try dictionary.removeObject(forKey: key) {
        return object
      }
    }

    return nil
  }

  mutating func clear() {
    _ = storage.pop(depth - 3)
  }

  var isEmpty: Bool { storage.isEmpty }
  var depth: Int { storage.depth }

  func current() throws -> Object {
    guard let dict = peek() else {
      throw Error.dictionaryStackUnderflow
    }
    return dict
  }

  func currentDictionary() throws -> DictionaryValue {
    try current().value(as: DictionaryValue.self)
  }

  func userDictionary() throws -> DictionaryValue {
    try storage[storage.index(storage.endIndex, offsetBy: -3)].value(as: DictionaryValue.self)
  }

  func globalDictionary() throws -> DictionaryValue {
    try storage[storage.index(storage.endIndex, offsetBy: -2)].value(as: DictionaryValue.self)
  }

  func systemDictionary() throws -> DictionaryValue {
    try storage[storage.index(storage.endIndex, offsetBy: -1)].value(as: DictionaryValue.self)
  }

  func peek() -> Object? {
    storage.peek()
  }

  func peek(count: Int) throws -> some Collection<Object> {
    return try peek(bounds: 0..<count)
  }

  func peek(bounds: Range<Int>) throws -> some Collection<Object> {
    let startIndex = storage.index(storage.startIndex, offsetBy: bounds.lowerBound)
    let endIndex = storage.index(storage.startIndex, offsetBy: bounds.upperBound)
    guard startIndex < endIndex && endIndex <= storage.endIndex else {
      throw Error.dictionaryStackUnderflow
    }
    return storage[startIndex..<endIndex]
  }

  mutating func pop() throws -> Object {
    guard storage.depth > 3 else {
      throw Error.dictionaryStackUnderflow
    }
    return storage.pop()
  }

  mutating func push(_ element: Object) throws {

    _ = try element.value(as: DictionaryValue.self)

    storage.push(element)
  }

  subscript(position: Storage.Index) -> Object {
    get throws {
      guard storage.startIndex < position else {
        throw Error.dictionaryStackUnderflow
      }
      return storage[position]
    }
  }

  func forEach(_ block: (Object) throws -> Void) throws {
    try storage.forEach(block)
  }

}
