//
//  FileSystemDevice.swift
//

import Foundation

/// Metadata returned by the filename form of the PostScript `status` operator.
public struct NamedFileStatus: Equatable, Sendable {

  /// The file's implementation-defined page usage.
  public let pages: Int32
  /// The file's logical size in bytes.
  public let bytes: Int32
  /// The file's last-reference time in device-defined units.
  public let referenced: Int32
  /// The file's creation time in device-defined units.
  public let created: Int32

  /// Creates filename status metadata.
  public init(pages: Int32, bytes: Int32, referenced: Int32, created: Int32) {
    self.pages = pages
    self.bytes = bytes
    self.referenced = referenced
    self.created = created
  }
}

/// An optional file-device capability for named file-system operations.
public protocol FileSystemDevice: FileDevice {

  /// Returns metadata for a named regular file, or `nil` when it does not exist.
  func status(name: String) throws -> NamedFileStatus?

  /// Deletes a named file.
  func delete(name: String) throws

  /// Renames a named file on this device.
  func rename(name: String, to newName: String) throws

  /// Returns regular-file names matching a PostScript filename template.
  func fileNames(matching template: String) throws -> [String]
}

extension FileSystemDevice {

  /// Returns no metadata when a conformer does not implement named files.
  public func status(name: String) throws -> NamedFileStatus? { nil }

  /// Rejects deletion when a conformer does not implement named files.
  public func delete(name: String) throws { throw Error.invalidFileAccess }

  /// Rejects renaming when a conformer does not implement named files.
  public func rename(name: String, to newName: String) throws { throw Error.invalidFileAccess }

  /// Returns no matches when a conformer does not implement enumeration.
  public func fileNames(matching template: String) throws -> [String] { [] }
}

enum FileSystemErrorTranslation {

  static func translate(_ error: Swift.Error) -> Error {
    if let error = error as? Error { return error }

    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      switch CocoaError.Code(rawValue: nsError.code) {
      case .fileNoSuchFile, .fileReadNoSuchFile:
        return .undefinedFilename
      case .fileReadNoPermission, .fileWriteNoPermission, .fileWriteVolumeReadOnly:
        return .invalidFileAccess
      default:
        return .ioError
      }
    }

    if nsError.domain == NSPOSIXErrorDomain {
      switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
      case .ENOENT:
        return .undefinedFilename
      case .EACCES, .EPERM, .EROFS:
        return .invalidFileAccess
      default:
        return .ioError
      }
    }

    return .ioError
  }
}
