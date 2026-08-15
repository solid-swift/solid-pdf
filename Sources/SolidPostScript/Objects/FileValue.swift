//
//  FileValue.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Object {

  /// Performs the ``file`` operation.
  public static func file(_ file: File, access: ObjectAccess, vm: VM, kind: ObjectKind) -> Object {
    Self(value: FileValue(file: file, vm: vm), kind: kind)
  }

  /// Performs the ``dataFile`` operation.
  public static func dataFile(content: Data, access: ObjectAccess, vm: VM, kind: ObjectKind) -> Object {
    let mode: File.Mode = access == .unlimited ? .readWrite : .read
    return Self(value: FileValue(file: DataFile(data: content, mode: mode), vm: vm), kind: kind)
  }

}

/// A PostScript file value.
public struct FileValue: CompositeValue, ObjectSource {

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .file
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``file`` value.
  public let file: File
  /// The ``access`` value.
  public private(set) var access: ObjectAccess
  /// The ``vm`` value.
  public let vm: VM

  init(file: File, vm: VM) {
    self.file = file
    self.access = file.mode.access
    self.vm = vm
  }

  init(sharing: FileValue, access: ObjectAccess) {
    self.file = sharing.file
    self.access = access
    self.vm = sharing.vm
  }

  /// The ``name`` value.
  public var name: String { file.name }
  /// The ``mode`` value.
  public var mode: File.Mode { file.mode }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) throws {
    try context.execution.push(source: Object(value: self, kind: kind), in: context)
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
  }

  /// Performs the ``makeIterator`` operation.
  public func makeIterator(context: isolated Context) throws -> any ObjectIterator {
    let scanner = try Scanner(file: file)
    return TokenObjectIterator(scanner: scanner)
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return file === other.file
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(file))
  }

  /// A debug representation of this value.
  public var debugString: String {
    "name: \(file.name), mode: \(file.mode)"
  }
}
