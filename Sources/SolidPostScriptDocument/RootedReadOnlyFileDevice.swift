import Foundation
import SolidPostScript

/// A searched, read-only file device confined to explicitly supplied directory roots.
public struct RootedReadOnlyFileDevice: FileSystemDevice, Sendable {
  public let searched = true
  public let name: String
  private let roots: [URL]

  /// Creates a rooted file device after resolving every root's symbolic links.
  public init(name: String = "os", roots: [URL]) throws {
    self.name = name
    self.roots = try roots.map { root in
      let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue
      else { throw PostScriptDocumentError.malformedDSC(offset: 0, message: "Unreadable allowlisted directory") }
      return resolved
    }
  }

  public func open(
    name: String,
    mode: FileMode,
    openMethod: FileOpenMethod
  ) throws -> any File {
    guard mode == .read, case .existingOnly = openMethod else { throw SolidPostScript.Error.invalidFileAccess }
    guard let url = resolve(name), FileManager.default.fileExists(atPath: url.path) else {
      throw SolidPostScript.Error.undefinedFilename
    }
    return try OSFile(name: url.path, mode: .read, openMethod: .existingOnly)
  }

  public func status(name: String) throws -> NamedFileStatus? {
    guard let url = resolve(name),
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else { return nil }
    return NamedFileStatus(pages: 0, bytes: Int32(clamping: size.int64Value), referenced: 0, created: 0)
  }

  public func fileNames(matching template: String) throws -> [String] { [] }

  private func resolve(_ name: String) -> URL? {
    for root in roots {
      let candidate = if name.hasPrefix("/") {
        URL(fileURLWithPath: name)
      } else {
        root.appendingPathComponent(name)
      }
      let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
      let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
      guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else { continue }
      return resolved
    }
    return nil
  }
}
