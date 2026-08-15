//
//  StdIOFileDevices.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A PostScript std iofile devices.
public enum StdIOFileDevices: FileDevice {

  /// A PostScript name.
  public enum Name: String, Sendable {
    case input = "stdin"
    case output = "stdout"
    case error = "stderr"
  }

  case instance(name: Name)

  /// The ``searched`` value.
  public var searched: Bool { false }

  /// The ``name`` value.
  public var name: String {
    switch self {
    case .instance(name: let name):
      name.rawValue
    }
  }

  /// Performs the ``open`` operation.
  public func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {

    guard name == "", case .instance(let name) = self else {
      throw Error.undefinedFilename
    }

    switch (name, mode, openMethod) {
    case (.input, .read, .existingOnly):
      return OSFile(handle: .standardInput, name: name.rawValue, mode: mode, openMethod: openMethod)
    case (.output, .write, .truncateOrCreate):
      return OSFile(handle: .standardOutput, name: name.rawValue, mode: mode, openMethod: openMethod)
    case (.error, .write, .truncateOrCreate):
      return OSFile(handle: .standardOutput, name: name.rawValue, mode: mode, openMethod: openMethod)
    default:
      throw Error.invalidFileAccess
    }
  }

}
