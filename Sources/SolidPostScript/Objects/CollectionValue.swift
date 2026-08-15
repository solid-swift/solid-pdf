//
//  CollectionValue.swift
//
//
//  Created by Kevin Wooten on 7/2/24.
//

import Foundation

/// A PostScript collection value.
public protocol CollectionValue: CompositeValue, ObjectSource {

  typealias Storage = [Object]
  typealias StorageRange = Range<Storage.Index>
  typealias SubRange = Range<UInt>
  typealias SubRangeExpression = RangeExpression<UInt>

  var count: UInt { get }
  var range: SubRange { get }

  func object(at position: UInt, for access: Object.Access) throws -> Object
  func objects(in range: Range<UInt>, for access: Object.Access) throws -> ArraySlice<Object>

  func forEachUnchecked(_ block: (Object) throws -> Void) rethrows
}

extension CollectionValue {

  /// Performs the ``object`` operation.
  public func object(at position: UInt) throws -> Object {
    try object(at: position, for: .read)
  }

  /// Performs the ``objects`` operation.
  public func objects(in range: Range<UInt>) throws -> ArraySlice<Object> {
    try objects(in: range, for: .read)
  }

  /// Performs the ``makeIterator`` operation.
  public func makeIterator(context: isolated Context) throws -> any ObjectIterator {
    return CollectionIterator(collection: self)
  }

}

extension Collection where Element == Object {

  internal func checkStorage(in vm: VM) throws {
    for element in self {
      try element.checkStorage(in: vm)
    }
  }
}
