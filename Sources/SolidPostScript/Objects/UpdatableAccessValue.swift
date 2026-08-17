//
//  UpdatableAccessValue.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation

/// An PostScript updatable access value.
public protocol UpdatableAccessValue: AccessedValue {

  static var maxAccess: ObjectAccess { get }

  var access: ObjectAccess { get }
  mutating func setAccess(to access: ObjectAccess) throws

}

extension UpdatableAccessValue {

  /// The ``maxAccess`` value.
  public static var maxAccess: ObjectAccess { .unlimited }

  /// Performs the ``reduceAccess`` operation.
  public mutating func reduceAccess(to reducedAccess: ObjectAccess) throws {
    try access.canReduce(to: reducedAccess)
    try setAccess(to: reducedAccess)
  }

}
