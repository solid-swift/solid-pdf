//
//  FileMode.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A PostScript file mode.
public enum FileMode: Sendable {
  case read
  case write
  case readWrite
}

extension FileMode {

  /// Creates an instance.
  public init(string: String) throws {
    self =
      switch string {
      case "r": .read
      case "w", "a": .write
      case "r+", "w+", "a+": .readWrite
      default: throw Error.invalidFileAccess
      }
  }

  /// The ``access`` value.
  public var access: ObjectAccess {
    switch self {
    case .readWrite: .unlimited
    case .write: .unlimited
    case .read: .readOnly
    }
  }

}

extension FileMode: CustomStringConvertible {

  /// The ``description`` value.
  public var description: String {
    switch self {
    case .read: "read"
    case .write: "write"
    case .readWrite: "read, write"
    }
  }
}
