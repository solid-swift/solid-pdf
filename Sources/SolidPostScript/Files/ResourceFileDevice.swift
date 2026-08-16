import Foundation

/// Metadata used when discovering an external PostScript resource file.
public struct ResourceFileMetadata: Equatable, Sendable {
  /// The file's encoded size in bytes.
  public let byteCount: Int

  /// Creates resource-file metadata.
  public init(byteCount: Int) {
    self.byteCount = byteCount
  }
}

/// A file device that can discover files used by the PostScript resource system.
public protocol ResourceFileDevice: FileDevice {
  /// Returns metadata for an existing resource file, or `nil` when it does not exist.
  func resourceFileMetadata(name: String) throws -> ResourceFileMetadata?

  /// Returns the immediate file names in a resource directory.
  func resourceFileNames(in directory: String) throws -> [String]
}
