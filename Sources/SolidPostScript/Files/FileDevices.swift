//
//  FileDevices.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A registry of file devices available to an interpreter.
public final class FileDevices: Sendable {

  /// The ``registeredDevices`` value.
  public let registeredDevices: [FileDevice]

  /// Creates an instance.
  public init(devices: [FileDevice] = defaultDevices) {
    self.registeredDevices = devices.sorted { ($0.searched ? 1 : 0) > ($1.searched ? 1 : 0) }
  }

  func device(named name: String) throws -> any FileDevice {
    guard let device = registeredDevices.first(where: { $0.name == name }) else {
      throw Error.undefined
    }
    return device
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
    let parsed = parseDeviceFileName(name)
    guard let deviceName = parsed.device else { throw Error.undefinedFilename }
    return try open(device: deviceName, name: parsed.name, mode: mode, openMethod: openMethod)
  }

  func resourceFileMetadata(name: String) throws -> ResourceFileMetadata? {
    let parsed = parseDeviceFileName(name)
    if let deviceName = parsed.device {
      guard let device = registeredDevices.first(where: { $0.name == deviceName }) as? any ResourceFileDevice else {
        return nil
      }
      return try device.resourceFileMetadata(name: parsed.name)
    }
    for device in registeredDevices where device.searched {
      guard let resourceDevice = device as? any ResourceFileDevice else { continue }
      if let metadata = try resourceDevice.resourceFileMetadata(name: name) { return metadata }
    }
    return nil
  }

  func resourceFileNames(in directory: String) throws -> [String] {
    let parsed = parseDeviceFileName(directory)
    if let deviceName = parsed.device {
      guard let device = registeredDevices.first(where: { $0.name == deviceName }) as? any ResourceFileDevice else {
        return []
      }
      return try device.resourceFileNames(in: parsed.name)
    }
    return try registeredDevices.compactMap { $0 as? any ResourceFileDevice }
      .filter(\.searched)
      .flatMap { try $0.resourceFileNames(in: directory) }
  }

  private func parseDeviceFileName(_ value: String) -> (device: String?, name: String) {
    guard value.first == "%" else { return (nil, value) }
    let deviceStart = value.index(after: value.startIndex)
    guard let deviceEnd = value[deviceStart...].firstIndex(of: "%") else {
      return (String(value[deviceStart...]), "")
    }
    let nameStart = value.index(after: deviceEnd)
    return (String(value[deviceStart..<deviceEnd]), String(value[nameStart...]))
  }

}
