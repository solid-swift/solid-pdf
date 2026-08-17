//
//  OSFileDevice.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A PostScript operating-system file device.
public enum OSFileDevice: ResourceFileDevice, FileSystemDevice {
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
    } catch {
      let translated = FileSystemErrorTranslation.translate(error)
      if translated == .undefinedFilename { return nil }
      throw translated
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

  /// Returns metadata for a named operating-system file.
  public func status(name: String) throws -> NamedFileStatus? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: name)
      guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }

      let byteCount = max(0, (attributes[.size] as? NSNumber)?.int64Value ?? 0)
      let referenced = attributes[.modificationDate] as? Date ?? Date(timeIntervalSinceReferenceDate: 0)
      let created = attributes[.creationDate] as? Date ?? referenced
      return NamedFileStatus(
        pages: Int32(clamping: byteCount / 1024 + (byteCount.isMultiple(of: 1024) ? 0 : 1)),
        bytes: Int32(clamping: byteCount),
        referenced: Self.postScriptTime(referenced),
        created: Self.postScriptTime(created)
      )
    } catch {
      let translated = FileSystemErrorTranslation.translate(error)
      if translated == .undefinedFilename { return nil }
      throw translated
    }
  }

  /// Deletes a named operating-system file.
  public func delete(name: String) throws {
    do {
      try Self.requireRegularFile(name)
      try FileManager.default.removeItem(atPath: name)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  /// Renames a named operating-system file.
  public func rename(name: String, to newName: String) throws {
    do {
      try Self.requireRegularFile(name)
      try FileManager.default.moveItem(atPath: name, toPath: newName)
    } catch {
      throw FileSystemErrorTranslation.translate(error)
    }
  }

  /// Enumerates operating-system files matching a PostScript template.
  public func fileNames(matching template: String) throws -> [String] {
    guard template.contains("*") || template.contains("?") || template.contains("\\") else {
      return try status(name: template) == nil ? [] : [template]
    }
    guard let regex = template.asTemplateRegex(pathSeparatorSensitive: true) else { return [] }

    let prefix = Self.literalDirectoryPrefix(of: template)
    let root = prefix.isEmpty ? "." : prefix
    let rootURL = URL(fileURLWithPath: root, isDirectory: true)
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]

    guard let enumerator = FileManager.default.enumerator(
      at: rootURL,
      includingPropertiesForKeys: keys,
      options: []
    ) else {
      return []
    }

    var matches: [String] = []
    for case let url as URL in enumerator {
      do {
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isSymbolicLink == true {
          if values.isDirectory == true { enumerator.skipDescendants() }
          continue
        }
        guard values.isRegularFile == true else { continue }

        let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
        let candidate: String
        if root == "." {
          candidate = relative
        } else if root == "/" {
          candidate = "/\(relative)"
        } else {
          candidate = "\(root)/\(relative)"
        }
        if (try? regex.wholeMatch(in: candidate)) != nil { matches.append(candidate) }
      } catch {
        throw FileSystemErrorTranslation.translate(error)
      }
    }
    return matches.sorted()
  }

  private static func literalDirectoryPrefix(of template: String) -> String {
    var escaped = false
    var wildcardIndex = template.endIndex
    for index in template.indices {
      let character = template[index]
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "*" || character == "?" {
        wildcardIndex = index
        break
      }
    }

    let literal = template[..<wildcardIndex]
    guard let separator = literal.lastIndex(of: "/") else { return "." }
    if separator == template.startIndex { return "/" }
    return unescaped(String(template[..<separator]))
  }

  private static func unescaped(_ value: String) -> String {
    var result = ""
    var escaped = false
    for character in value {
      if escaped {
        result.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        result.append(character)
      }
    }
    if escaped { result.append("\\") }
    return result
  }

  private static func postScriptTime(_ date: Date) -> Int32 {
    Int32(clamping: Int64(date.timeIntervalSinceReferenceDate))
  }

  private static func requireRegularFile(_ name: String) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: name)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw Error.invalidFileAccess
    }
  }

}
