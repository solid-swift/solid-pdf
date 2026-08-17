//
//  CollectionIterator.swift
//
//
//  Created by Kevin Wooten on 7/8/24.
//

import Foundation

/// A PostScript collection iterator.
public class CollectionIterator: ObjectIterator {

  var collection: CollectionValue
  var currentIndex: Int

  /// Creates an instance.
  public init(collection: CollectionValue, currentIndex: Int = -1) {
    self.collection = collection
    self.currentIndex = currentIndex
  }

  var isExhausted: Bool {
    currentIndex >= Int(collection.count) - 1
  }

  /// Returns the next PostScript object, when available.
  public func next(context: isolated Context) throws -> Object? {
    currentIndex += 1
    guard currentIndex < collection.count else {
      return nil
    }
    return try collection.object(at: UInt(currentIndex), for: .execute)
  }

}
