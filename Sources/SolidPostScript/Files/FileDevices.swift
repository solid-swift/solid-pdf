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
    self.registeredDevices = devices
  }

  func replacing(_ device: any FileDevice) -> FileDevices {
    FileDevices(devices: registeredDevices.filter { $0.name != device.name } + [device])
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
    let parsed = PostScriptFileName(name)

    if let deviceName = parsed.device {
      return try open(device: deviceName, name: parsed.name, mode: mode, openMethod: openMethod)
    }

    return try search(name: parsed.name, mode: mode, openMethod: openMethod)
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

  func resourceFileMetadata(name: String) throws -> ResourceFileMetadata? {
    let parsed = PostScriptFileName(name)
    if let deviceName = parsed.device {
      guard let device = registeredDevices.first(where: { $0.name == deviceName }) as? any ResourceFileDevice else {
        return nil
      }
      return try device.resourceFileMetadata(name: parsed.name)
    }
    for device in registeredDevices where device.searched {
      guard let resourceDevice = device as? any ResourceFileDevice else { continue }
      if let metadata = try resourceDevice.resourceFileMetadata(name: parsed.name) { return metadata }
    }
    return nil
  }

  func resourceFileNames(in directory: String) throws -> [String] {
    let parsed = PostScriptFileName(directory)
    if let deviceName = parsed.device {
      guard let device = registeredDevices.first(where: { $0.name == deviceName }) as? any ResourceFileDevice else {
        return []
      }
      return try device.resourceFileNames(in: parsed.name)
    }
    return try registeredDevices.compactMap { $0 as? any ResourceFileDevice }
      .filter(\.searched)
      .flatMap { try $0.resourceFileNames(in: parsed.name) }
  }

  func status(name: String) throws -> NamedFileStatus? {
    let parsed = PostScriptFileName(name)
    if let deviceName = parsed.device {
      guard !parsed.isUnnamedDevice else { return nil }
      guard let device = fileSystemDevice(named: deviceName) else { return nil }
      return try device.status(name: parsed.name)
    }
    for device in fileSystemDevices where device.searched {
      if let status = try device.status(name: parsed.name) { return status }
    }
    return nil
  }

  func delete(name: String) throws {
    let parsed = PostScriptFileName(name)
    if let deviceName = parsed.device {
      guard !parsed.isUnnamedDevice else { throw Error.invalidFileAccess }
      guard let device = fileSystemDevice(named: deviceName) else { throw Error.undefinedFilename }
      try device.delete(name: parsed.name)
      return
    }

    for device in fileSystemDevices where device.searched {
      guard try device.status(name: parsed.name) != nil else { continue }
      try device.delete(name: parsed.name)
      return
    }
    throw Error.undefinedFilename
  }

  func rename(name: String, to newName: String) throws {
    let source = PostScriptFileName(name)
    let destination = PostScriptFileName(newName)
    guard !source.isUnnamedDevice, !destination.isUnnamedDevice else {
      throw Error.invalidFileAccess
    }

    if let sourceDevice = source.device, let destinationDevice = destination.device,
      sourceDevice != destinationDevice
    {
      throw Error.invalidFileAccess
    }

    if let deviceName = source.device ?? destination.device {
      guard let device = fileSystemDevice(named: deviceName) else { throw Error.undefinedFilename }
      try device.rename(name: source.name, to: destination.name)
      return
    }

    for device in fileSystemDevices where device.searched {
      guard try device.status(name: source.name) != nil else { continue }
      try device.rename(name: source.name, to: destination.name)
      return
    }
    throw Error.undefinedFilename
  }

  func fileNames(matching template: String) throws -> [String] {
    let parsed = PostScriptFileName(template)
    if let deviceTemplate = parsed.device {
      guard !parsed.isUnnamedDevice, let regex = deviceTemplate.asTemplateRegex else { return [] }
      return try fileSystemDevices.flatMap { device in
        guard (try? regex.wholeMatch(in: device.name)) != nil else { return [String]() }
        return try device.fileNames(matching: parsed.name).map { "%\(device.name)%\($0)" }
      }
    }

    return try fileSystemDevices.filter(\.searched).flatMap {
      try $0.fileNames(matching: parsed.name)
    }
  }

  private var fileSystemDevices: [any FileSystemDevice] {
    registeredDevices.compactMap { $0 as? any FileSystemDevice }
  }

  private func fileSystemDevice(named name: String) -> (any FileSystemDevice)? {
    registeredDevices.first(where: { $0.name == name }) as? any FileSystemDevice
  }

}
