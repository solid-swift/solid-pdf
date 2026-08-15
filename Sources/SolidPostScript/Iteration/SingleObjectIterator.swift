//
//  SingleObjectIterator.swift
//
//
//  Created by Kevin Wooten on 7/8/24.
//

import Foundation

/// A PostScript single object iterator.
public class SingleObjectIterator: ObjectIterator {

  private var object: Object?

  /// Creates an instance.
  public init(object: Object) {
    self.object = object
  }

  /// Returns the next PostScript object, when available.
  public func next(context: isolated Context) throws -> Object? {
    guard let object else {
      return nil
    }
    self.object = nil
    return object
  }

}
