//
//  FileDevices.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A registry of file devices available to an interpreter.
public final class FileDevices {

  /// The ``registeredDevices`` value.
  public private(set) var registeredDevices: [FileDevice]

  /// Creates an instance.
  public init(devices: [FileDevice] = defaultDevices) {
    self.registeredDevices = devices.sorted { ($0.searched ? 1 : 0) > ($1.searched ? 1 : 0) }
  }

  /// The ``defaultDevices`` value.
  public static let defaultDevices: [FileDevice] = [
    OSFileDevice.instance,
    StdIOFileDevices.instance(name: .input),
    StdIOFileDevices.instance(name: .output),
    StdIOFileDevices.instance(name: .error),
  ]

  /// Performs the ``open`` operation.
  public func open(name: String, mode modeString: String) throws -> File {

    let mode = try FileMode(string: modeString)
    let openMethod = try FileOpenMethod(string: modeString)

    guard !name.hasPrefix("%") else {

      return try open(deviceFileName: name, mode: mode, openMethod: openMethod)
    }

    return try search(name: name, mode: mode, openMethod: openMethod)
  }

  private func search(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> File {

    for device in registeredDevices where device.searched {
      do {
        return try device.open(name: name, mode: mode, openMethod: openMethod)
      } catch Error.undefinedFilename {
        continue
      }
    }

    throw Error.undefinedFilename
  }

  /// Performs the ``open`` operation.
  public func open(device deviceName: String, name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> File {

    guard let device = registeredDevices.first(where: { $0.name == deviceName }) else {
      throw Error.undefinedFilename
    }

    return try device.open(name: name, mode: mode, openMethod: openMethod)
  }

  private func open(deviceFileName name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> File {

    let deviceNameStart = name.index(after: name.startIndex)
    guard let deviceNameEnd = name.dropFirst().firstIndex(of: "%") else {

      let deviceName = String(name[deviceNameStart...])

      return try open(device: deviceName, name: "", mode: mode, openMethod: openMethod)
    }

    let deviceName = String(name[deviceNameStart..<deviceNameEnd])

    guard let fileNameStart = name.index(name.startIndex, offsetBy: 1, limitedBy: name.endIndex) else {

      return try open(device: deviceName, name: "", mode: mode, openMethod: openMethod)
    }

    let fileName = String(name[fileNameStart...])

    return try open(device: deviceName, name: fileName, mode: mode, openMethod: openMethod)
  }

}
