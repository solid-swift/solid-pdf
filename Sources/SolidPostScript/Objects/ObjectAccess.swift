//
//  ObjectAccess.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An PostScript object access.
public enum ObjectAccess: Int, Equatable, Comparable, Sendable {

  case noAccess = 0
  case executeOnly = 1
  case readOnly = 2
  case unlimited = 3

  var isReadAllowed: Bool {
    switch self {
    case .unlimited, .readOnly:
      true
    case .executeOnly, .noAccess:
      false
    }
  }

  var isWriteAllowed: Bool {
    guard case .unlimited = self else {
      return false
    }
    return true
  }

  var isExecuteAllowed: Bool {
    switch self {
    case .unlimited, .readOnly, .executeOnly:
      true
    case .noAccess:
      false
    }
  }

  func check(_ access: Object.Access) throws {
    let allowed =
      switch (self, access) {
      case (.unlimited, _): true
      case (.readOnly, .read), (.readOnly, .execute): true
      case (.executeOnly, .execute): true
      case (.noAccess, _): false
      case (.readOnly, _), (.executeOnly, _): false
      }
    if !allowed {
      throw Error.invalidAccess
    }
  }

  func canReduce(to reducedAcces: ObjectAccess) throws {
    guard self >= reducedAcces else {
      throw Error.invalidAccess
    }
  }

  /// Performs the ``lhs`` operation.
  public static func < (lhs: ObjectAccess, rhs: ObjectAccess) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}
