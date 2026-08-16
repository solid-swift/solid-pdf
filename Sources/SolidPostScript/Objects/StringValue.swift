//
//  StringValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation
import SolidCore
import Synchronization

extension Object {

  /// Performs the ``string`` operation.
  public static func string(_ string: String, access: ObjectAccess, vm: VM, kind: ObjectKind) -> Self {
    Self(value: StringValue(string: string, access: access, vm: vm), kind: kind)
  }

  /// Performs the ``string`` operation.
  public static func string(_ data: Data, access: ObjectAccess, vm: VM, kind: ObjectKind) -> Self {
    Self(value: StringValue(data: data, access: access, vm: vm), kind: kind)
  }

  /// Performs the ``string`` operation.
  public static func string(_ data: some Collection<UInt8>, access: ObjectAccess, vm: VM, kind: ObjectKind) -> Self {
    Self(value: StringValue(data: Data(data), access: access, vm: vm), kind: kind)
  }

  /// Performs the ``string`` operation.
  public static func string<R: StringValue.SubRangeExpression>(sharing: StringValue, subRange: R, kind: ObjectKind)
    throws -> Self
  {
    Self(value: try StringValue(sharing: sharing, subRange: subRange.relative(to: 0..<sharing.count)), kind: kind)
  }
}

/// A PostScript string value.
public struct StringValue: CompositeValue, ObjectSource, VMStoredCompositeValue {

  /// The type used to represent ``Storage``.
  public typealias Storage = Data
  /// The type used to represent ``StorageRange``.
  public typealias StorageRange = Range<Data.Index>
  /// The type used to represent ``SubRange``.
  public typealias SubRange = Range<UInt>
  /// The type used to represent ``SubRangeExpression``.
  public typealias SubRangeExpression = RangeExpression<UInt>

  /// The PostScript object type represented by this value.
  public static let objectType: ObjectType = .string
  /// The default execution kind for this value.
  public static let defaultKind: ObjectKind = .literal

  /// The ``access`` value.
  public private(set) var access: ObjectAccess = Self.maxAccess

  private final class Shared: Sendable {
    let value: Mutex<Storage>
    let vm: VM
    let allocation: VMAllocation

    init(value: Storage, vm: VM) {
      self.value = Mutex(value)
      self.vm = vm
      self.allocation = VMAllocationContext.allocation(in: vm, bytes: value.count + 16)
      self.allocation.attach(
        owner: self,
        clear: { [weak self] in self?.value.withLock { $0.removeAll(keepingCapacity: false) } }
      )
    }
  }

  private let ref: Shared
  private let rootLease: VMRootLease
  /// The ``refRange`` value.
  public let refRange: StorageRange

  /// Creates an instance.
  public init(string: String, access: ObjectAccess, vm: VM) {
    let data = string.data(using: .isoLatin1).neverNil()
    self.init(data: data, access: access, vm: vm)
  }

  /// Creates an instance.
  public init(data: Storage, access: ObjectAccess, vm: VM) {
    self.ref = Shared(value: data, vm: vm)
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
    self.refRange = data.indices
    self.access = access
  }

  /// Creates an instance.
  public init(sharing: Self, subRange: SubRange) throws {
    self.ref = sharing.ref
    self.rootLease = sharing.rootLease
    self.refRange = try sharing.ref.value.withLock {
      try sharing.refRange.select(subRange: subRange, in: $0)
    }
    self.access = sharing.access
  }

  /// Performs the ``setAccess`` operation.
  public mutating func setAccess(to access: ObjectAccess) throws {
    self.access = access
  }

  /// The ``vm`` value.
  public var vm: VM { ref.vm }
  var allocation: VMAllocation { ref.allocation }
  var allocationFootprint: Int { ref.value.withLock { $0.count + 16 } }

  /// The ``count`` value.
  public var count: UInt {
    ref.value.withLock { UInt($0.distance(from: refRange.lowerBound, to: refRange.upperBound)) }
  }
  /// The ``range`` value.
  public var range: SubRange { 0..<count }

  /// Performs the ``character`` operation.
  public func character(at position: UInt) throws -> UInt8 {
    try access.check(.read)
    return try ref.value.withLock { value in
      let index = try refRange.select(subRange: position..<position + 1, in: value).lowerBound
      return value[index]
    }
  }

  /// Performs the ``characters`` operation.
  public func characters(in subRange: SubRange) throws -> Data {
    try access.check(.read)
    return try ref.value.withLock { value in
      let subRange = try refRange.select(subRange: subRange, in: value)
      return value[subRange]
    }
  }

  /// Performs the ``updateCharacter`` operation.
  public func updateCharacter(_ character: UInt8, at position: UInt) throws {
    try access.check(.write)
    try VMGraph.withLock {
      try ref.value.withLock { value in
        let index = try refRange.select(subRange: position..<position + 1, in: value).lowerBound
        value[index] = character
      }
    }
  }

  /// Performs the ``updateCharacters`` operation.
  public func updateCharacters(_ characters: some Collection<UInt8>, startingAt position: UInt) throws {
    try access.check(.write)
    try VMGraph.withLock {
      try ref.value.withLock { value in
        let range = try refRange.select(subRange: position..<position + UInt(characters.count), in: value)
        value.replaceSubrange(range, with: characters)
      }
    }
  }

  /// Performs the ``compare`` operation.
  public func compare(_ other: StringValue) -> ComparisonResult {
    return rangedValueSnapshot < other.rangedValueSnapshot
  }

  /// Compares the readable portions of two string objects.
  func compareReadable(_ other: StringValue) throws -> ComparisonResult {
    try access.check(.read)
    try other.access.check(.read)
    return compare(other)
  }

  /// Performs the ``firstRange`` operation.
  public func firstRange(of subdata: StringValue) throws -> SubRange? {
    let value = try characters(in: range)
    let sought = try subdata.characters(in: subdata.range)
    guard let found = value.firstRange(of: sought, in: value.indices) else {
      return nil
    }

    let startIndex = UInt(value.distance(from: value.startIndex, to: found.lowerBound))
    let endIndex = startIndex + UInt(found.count)
    return startIndex..<endIndex
  }

  /// Records restorable state in a snapshot builder.
  public func save(to snapshot: Snapshot.Builder) {
    // PLRM 3.7.3 explicitly excludes string contents from restore rollback.
  }

  /// Executes this value in the supplied interpreter context.
  public func execute(context: isolated Context, kind: ObjectKind, method: Object.AccessMethod) async throws {
    try context.execution.push(source: .init(value: self, kind: .executable), in: context)
  }

  /// Performs the ``makeIterator`` operation.
  public func makeIterator(context: isolated Context) throws -> any ObjectIterator {
    let scanner = try Scanner(content: rangedValueSnapshot)
    return TokenObjectIterator(scanner: scanner)
  }

  internal var string: String {
    String(data: rangedValueSnapshot, encoding: .isoLatin1).neverNil()
  }

  var readableString: String {
    get throws {
      String(data: try characters(in: range), encoding: .isoLatin1).neverNil()
    }
  }

  /// Returns whether this value equals another PostScript value.
  public func equals(_ other: any ObjectValue) throws -> Bool {
    switch other {
    case let otherString as StringValue:
      try access.check(.read)
      try otherString.access.check(.read)
      return rangedValueSnapshot == otherString.rangedValueSnapshot
    case let otherName as NameValue:
      return try readableString == otherName.value
    default:
      return false
    }
  }

  /// Hashes the value into the supplied hasher.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(rangedValueSnapshot)
  }

  /// A debug representation of this value.
  public var debugString: String {
    let value = valueSnapshot
    let slice = range.count != value.count ? "[\(range)]" : ""
    return #""\#(value[refRange].map(\.description).joined(separator: ", "))"\#(slice)""#
  }

  /// The value's printable string representation, when available.
  public var valueString: String? { string }

  /// Returns the PostScript token representation, when available.
  public func tokenString(kind: ObjectKind) -> String? {
    "(\(string))"
  }

  private var valueSnapshot: Storage {
    ref.value.withLock { $0 }
  }

  private var rangedValueSnapshot: Storage {
    ref.value.withLock { $0[refRange] }
  }

  func storedObject(kind: ObjectKind) -> VMStoredObject {
    let object = Object(value: self, kind: kind)
    let range = refRange
    let access = access
    return .reference(allocation: allocation, owner: ref, object: object) { [weak ref] in
      guard let ref else { return nil }
      return Object(value: Self(ref: ref, refRange: range, access: access), kind: kind)
    }
  }

  private init(ref: Shared, refRange: StorageRange, access: ObjectAccess) {
    self.ref = ref
    self.rootLease = VMRootLease(allocation: ref.allocation, owner: ref)
    self.refRange = refRange
    self.access = access
  }
}

extension StringValue: SnapshotIdentifiableValue {

  var snapshotIdentity: ObjectIdentifier { ObjectIdentifier(ref) }

}
