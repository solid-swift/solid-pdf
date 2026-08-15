//
//  ErrorHandlerValue.swift
//
import Foundation

/// A built-in value stored in the initial `errordict`.
enum ErrorHandlerValue: ObjectValue, Equatable {
  case standard(String)
  case handle

  static let objectType: ObjectType = .operator
  static let defaultKind: ObjectKind = .executable

  func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
    switch self {
    case .standard(let name):
      try context.executeDefaultErrorHandler(named: name)
    case .handle:
      try context.executeHandleError()
    }
  }

  func equals(_ other: any ObjectValue) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return self == other
  }

  func hash(into hasher: inout Hasher) {
    switch self {
    case .standard(let name):
      hasher.combine(0)
      hasher.combine(name)
    case .handle:
      hasher.combine(1)
    }
  }

  var valueString: String? { debugString }

  var debugString: String {
    switch self {
    case .standard(let name):
      name
    case .handle:
      "handleerror"
    }
  }
}
