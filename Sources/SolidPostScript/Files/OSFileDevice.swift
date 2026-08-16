//
//  OSFileDevice.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// An PostScript osfile device.
public enum OSFileDevice: ResourceFileDevice {
  case instance

  /// The ``searched`` value.
  public var searched: Bool { true }
  /// The ``name`` value.
  public var name: String { "os" }

  /// Performs the ``open`` operation.
  public func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {
    return try OSFile(name: name, mode: mode, openMethod: openMethod)
  }

  /// Returns metadata for an operating-system resource file.
  public func resourceFileMetadata(name: String) throws -> ResourceFileMetadata? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: name)
      guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
      return ResourceFileMetadata(byteCount: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    } catch {
      throw Error.ioError
    }
  }

  /// Enumerates the immediate files in an operating-system resource directory.
  public func resourceFileNames(in directory: String) throws -> [String] {
    do {
      return try FileManager.default.contentsOfDirectory(atPath: directory).filter { name in
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
      }
    } catch CocoaError.fileReadNoSuchFile {
      return []
    } catch {
      throw Error.ioError
    }
  }

}
