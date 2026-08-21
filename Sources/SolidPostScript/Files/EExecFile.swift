import Foundation
import SolidFont
import Synchronization

final class EExecFile: ContextualFile, FileSourceIdentityProviding, VMManagedFileGraph, Sendable {
  private enum SourceKind: Sendable {
    case file
    case string
  }

  private enum Transport: Sendable, Equatable {
    case undetermined
    case binary
    case hexadecimal
  }

  private struct State: Sendable {
    var transport = Transport.undetermined
    var pendingCiphertext = Data()
    var stringOffset: UInt = 0
    var cipher = Type1CipherState(seed: Type1CipherState.eexecSeed)
    var discardedPlaintextBytes = 0
    var closed = false
  }

  let name = "eexec"
  let mode: Mode = .read
  let isPositionable = false

  private let source: VMStoredObject
  private let sourceKind: SourceKind
  private let state = Mutex(State())
  private let operation = Mutex(false)

  init(source: Object) throws {
    switch source.value {
    case let file as FileValue:
      try file.access.check(.read)
      guard file.mode != .write else { throw Error.invalidFileAccess }
      sourceKind = .file
    case let string as StringValue:
      try string.access.check(.read)
      sourceKind = .string
    default:
      throw Error.typeCheck
    }
    self.source = VMStoredObject(source)
  }

  deinit {
    try? close()
  }

  var isClosed: Bool {
    state.withLock(\.closed)
  }

  func readByte() throws -> UInt8? {
    throw Error.ioError
  }

  func readByte(context: isolated Context) async throws -> UInt8? {
    try await read(max: 1, context: context)?.first
  }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    throw Error.ioError
  }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    guard let byte = try await readByte(context: context) else { return (nil, true) }
    guard predicate(byte) else {
      context.prependReadAhead(Data([byte]), to: self)
      return (nil, false)
    }
    return (byte, false)
  }

  func read(max: Int) throws -> Data? {
    throw Error.ioError
  }

  func read(max: Int, context: isolated Context) async throws -> Data? {
    try beginOperation()
    defer { endOperation() }
    guard max >= 0 else { throw Error.rangeCheck }
    guard max > 0 else { return Data() }
    try checkOpen()

    var plaintext = Data(capacity: max)
    while plaintext.count < max, let byte = try await nextPlaintextByte(context: context) {
      plaintext.append(byte)
    }
    return plaintext.isEmpty ? nil : plaintext
  }

  func write(contentsOf data: Data) throws {
    throw Error.ioError
  }

  func close() throws {
    state.withLock { $0.closed = true }
  }

  func close(context: isolated Context) async throws {
    let newlyClosed = state.withLock { state -> Bool in
      guard !state.closed else { return false }
      state.closed = true
      state.pendingCiphertext.removeAll(keepingCapacity: false)
      return true
    }
    if newlyClosed {
      context.closeEExecScope(for: self)
    }
  }

  var offset: Int { get throws { throw Error.ioError } }

  func setOffset(_ offset: Int) throws {
    throw Error.ioError
  }

  var available: Int { get throws { throw Error.ioError } }

  func available(context: isolated Context) async throws -> Int {
    try checkOpen()
    return -1
  }

  var size: Int { get throws { throw Error.ioError } }

  func flush() throws {
    throw Error.ioError
  }

  func flush(context: isolated Context) async throws {
    while try await read(max: 1, context: context) != nil {}
  }

  func reset() throws {}

  var retainedVMAllocations: [VMAllocation] {
    source.allocation.map { [$0] } ?? []
  }

  func identifyRetainedEdges(source allocation: VMAllocation) {
    source.identifyEdgeSource(allocation)
  }

  var ultimateSourceIdentity: ObjectIdentifier {
    guard sourceKind == .file else { return ObjectIdentifier(self) }
    return sourceFile.file.ultimateSourceIdentity
  }

  private func nextPlaintextByte(context: isolated Context) async throws -> UInt8? {
    while let ciphertext = try await nextCiphertextByte(context: context) {
      let result = state.withLock { state -> (byte: UInt8, discard: Bool) in
        let byte = state.cipher.decrypt(ciphertext)
        let discard = state.discardedPlaintextBytes < 4
        state.discardedPlaintextBytes += 1
        return (byte, discard)
      }
      if !result.discard { return result.byte }
    }
    return nil
  }

  private func nextCiphertextByte(context: isolated Context) async throws -> UInt8? {
    if state.withLock({ $0.transport == .undetermined }) {
      try await determineTransport(context: context)
    }
    if let pending = state.withLock({ state -> UInt8? in
      guard let byte = state.pendingCiphertext.first else { return nil }
      state.pendingCiphertext.removeFirst()
      return byte
    }) {
      return pending
    }

    switch state.withLock(\.transport) {
    case .undetermined:
      preconditionFailure("eexec transport detection did not complete")
    case .binary:
      return try await readRawByte(context: context)
    case .hexadecimal:
      return try await readHexadecimalByte(context: context)
    }
  }

  private func determineTransport(context: isolated Context) async throws {
    var prefix = Data(capacity: 8)
    while prefix.count < 4 {
      guard let byte = try await readRawByte(context: context) else { throw Error.ioError }
      prefix.append(byte)
    }

    if prefix.allSatisfy(Self.isHexadecimal) {
      while prefix.count < 8 {
        guard let byte = try await readRawByte(context: context), Self.isHexadecimal(byte) else {
          throw Error.ioError
        }
        prefix.append(byte)
      }
      let decoded = try Self.decodeHexadecimalPairs(prefix)
      state.withLock { state in
        state.transport = .hexadecimal
        state.pendingCiphertext = decoded
      }
    } else {
      state.withLock { state in
        state.transport = .binary
        state.pendingCiphertext = prefix
      }
    }
  }

  private func readHexadecimalByte(context: isolated Context) async throws -> UInt8? {
    var first: UInt8?
    while first == nil {
      guard let byte = try await readRawByte(context: context) else { return nil }
      if Self.isHexadecimal(byte) {
        first = byte
      } else if !Self.isWhitespace(byte) {
        throw Error.ioError
      }
    }
    guard let second = try await readRawByte(context: context), Self.isHexadecimal(second) else {
      throw Error.ioError
    }
    return Self.decodeHexadecimalPair(first!, second)
  }

  private func readRawByte(context: isolated Context) async throws -> UInt8? {
    switch sourceKind {
    case .file:
      return try await sourceFile.file.readByte(context: context)
    case .string:
      let offset = state.withLock(\.stringOffset)
      let string = sourceString
      guard offset < string.count else { return nil }
      let byte = try string.character(at: offset)
      state.withLock { $0.stringOffset += 1 }
      return byte
    }
  }

  private func checkOpen() throws {
    guard !isClosed else { throw Error.ioError }
  }

  private func beginOperation() throws {
    let acquired = operation.withLock { active -> Bool in
      guard !active else { return false }
      active = true
      return true
    }
    guard acquired else { throw Error.ioError }
  }

  private func endOperation() {
    operation.withLock { $0 = false }
  }

  private var sourceFile: FileValue {
    source.object.value as! FileValue
  }

  private var sourceString: StringValue {
    source.object.value as! StringValue
  }

  private static func isHexadecimal(_ byte: UInt8) -> Bool {
    Scanner.hexDigits.contains(byte)
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    Scanner.whitespace.contains(byte)
  }

  private static func decodeHexadecimalPairs(_ data: Data) throws -> Data {
    guard data.count.isMultiple(of: 2) else { throw Error.ioError }
    var result = Data(capacity: data.count / 2)
    var index = data.startIndex
    while index < data.endIndex {
      let first = data[index]
      index = data.index(after: index)
      let second = data[index]
      index = data.index(after: index)
      result.append(decodeHexadecimalPair(first, second))
    }
    return result
  }

  private static func decodeHexadecimalPair(_ first: UInt8, _ second: UInt8) -> UInt8 {
    hexadecimalValue(first) << 4 | hexadecimalValue(second)
  }

  private static func hexadecimalValue(_ byte: UInt8) -> UInt8 {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: preconditionFailure("Validated hexadecimal byte expected")
    }
  }
}
