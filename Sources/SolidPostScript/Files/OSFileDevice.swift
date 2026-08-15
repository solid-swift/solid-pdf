//
//  OSFileDevice.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// An PostScript osfile device.
public enum OSFileDevice: FileDevice {
  case instance

  /// The ``searched`` value.
  public var searched: Bool { true }
  /// The ``name`` value.
  public var name: String { "os" }

  /// Performs the ``open`` operation.
  public func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {
    return try OSFile(name: name, mode: mode, openMethod: openMethod)
  }

}
