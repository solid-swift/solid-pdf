//
//  DecodingFilterFile.swift
//  SolidPostScript
//
//  Created by Codex on 8/16/26.
//

import Foundation
import SolidIO
import Synchronization

final class DecodingFilterFile: ContextualFile, VMManagedFileGraph, Sendable {

  private enum SourceKind: Sendable, Equatable {
    case file
    case string
    case procedure
  }

  private struct State: Sendable {
    var encoded = Data()
    var decoded = Data()
    var stringConsumed = false
    var sourceEnded = false
    var reachedEOD = false
    var closed = false
  }

  let name: String
  let mode: Mode = .read
  let isPositionable = false

  private let codec: any IncrementalFilter
  private let source: VMStoredObject
  private let sourceKind: SourceKind
  private let closeSource: Bool
  private let state = Mutex(State())
  private let operation = Mutex(false)

  init(name: String, codec: any IncrementalFilter, source: Object, closeSource: Bool) throws {
    self.name = name
    self.codec = codec
    self.closeSource = closeSource

    switch source.value {
    case let file as FileValue:
      try file.checkReadable()
      self.sourceKind = .file
    case let string as StringValue:
      try string.access.check(.read)
      self.sourceKind = .string
    default:
      try source.checkProcedure()
      self.sourceKind = .procedure
    }
    self.source = VMStoredObject(source)
  }

  deinit {
    try? close()
  }

  var isClosed: Bool {
    state.withLock { $0.closed }
  }

  func readByte() throws -> UInt8? {
    try read(max: 1)?.first
  }

  func readByte(context: isolated Context) async throws -> UInt8? {
    try await read(max: 1, context: context)?.first
  }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    try withOperation {
      try fillWithoutContext(minimum: 1)
      let result = try state.withLock { state -> (UInt8?, Bool, Bool) in
        try checkOpenOrEOF(state)
        guard let byte = state.decoded.first else {
          return (nil, state.reachedEOD, state.reachedEOD)
        }
        guard predicate(byte) else { return (nil, false, false) }
        state.decoded.removeFirst()
        let shouldClose = state.reachedEOD && state.decoded.isEmpty
        return (byte, false, shouldClose)
      }
      if result.2 { try closeAfterEODWithoutContext() }
      return (result.0, result.1)
    }
  }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    try beginOperation()
    defer { endOperation() }
    try await fill(minimum: 1, context: context)
    let result = try state.withLock { state -> (UInt8?, Bool, Bool) in
      try checkOpenOrEOF(state)
      guard let byte = state.decoded.first else {
        return (nil, state.reachedEOD, state.reachedEOD)
      }
      guard predicate(byte) else { return (nil, false, false) }
      state.decoded.removeFirst()
      let shouldClose = state.reachedEOD && state.decoded.isEmpty
      return (byte, false, shouldClose)
    }
    if result.2 { try await closeAfterEOD(context: context) }
    return (result.0, result.1)
  }

  func read(max: Int) throws -> Data? {
    try withOperation {
      guard max >= 0 else { throw Error.rangeCheck }
      if max == 0 { return Data() }
      try fillWithoutContext(minimum: max)
      let result = try takeDecoded(max: max)
      if result.close { try closeAfterEODWithoutContext() }
      return result.data
    }
  }

  func read(max: Int, context: isolated Context) async throws -> Data? {
    try beginOperation()
    defer { endOperation() }
    guard max >= 0 else { throw Error.rangeCheck }
    if max == 0 { return Data() }
    try await fill(minimum: max, context: context)
    let result = try takeDecoded(max: max)
    if result.close { try await closeAfterEOD(context: context) }
    return result.data
  }

  func write(contentsOf data: Data) throws {
    throw Error.ioError
  }

  func close() throws {
    let shouldCloseSource = state.withLock { state -> Bool in
      guard !state.closed else { return false }
      state.closed = true
      state.decoded.removeAll()
      state.encoded.removeAll()
      return closeSource
    }
    if shouldCloseSource, sourceKind == .file {
      try sourceFile.file.close()
    }
  }

  func close(context: isolated Context) async throws {
    let shouldCloseSource = state.withLock { state -> Bool in
      guard !state.closed else { return false }
      state.closed = true
      state.decoded.removeAll()
      state.encoded.removeAll()
      return closeSource
    }
    if shouldCloseSource, sourceKind == .file {
      try await sourceFile.file.close(context: context)
    }
  }

  var offset: Int { get throws { throw Error.ioError } }

  func setOffset(_ offset: Int) throws {
    throw Error.ioError
  }

  var available: Int {
    get throws {
      try state.withLock { state in
        try checkOpenOrEOF(state)
        if !state.decoded.isEmpty { return state.decoded.count }
        return state.reachedEOD ? 0 : -1
      }
    }
  }

  func available(context: isolated Context) async throws -> Int {
    try beginOperation()
    defer { endOperation() }
    let current = try available
    guard current < 0 else { return current }
    try await fill(minimum: 1, context: context)
    return try available
  }

  var size: Int { get throws { throw Error.ioError } }

  func flush() throws {
    try withOperation {
      while true {
        state.withLock { $0.decoded.removeAll() }
        if state.withLock({ $0.reachedEOD }) { break }
        try fillWithoutContext(minimum: 1)
      }
      try closeAfterEODWithoutContext()
    }
  }

  func flush(context: isolated Context) async throws {
    try beginOperation()
    defer { endOperation() }
    while true {
      state.withLock { $0.decoded.removeAll() }
      if state.withLock({ $0.reachedEOD }) { break }
      try await fill(minimum: 1, context: context)
    }
    try await closeAfterEOD(context: context)
  }

  func reset() throws {}

  private func fillWithoutContext(minimum: Int) throws {
    while try needsDecodedData(minimum: minimum) {
      let encoded = if let pending = takeEncoded() {
        pending
      } else {
        try nextSourceChunkWithoutContext()
      }
      if let encoded {
        try process(encoded)
      } else {
        try finishDecoder()
      }
    }
  }

  private func fill(minimum: Int, context: isolated Context) async throws {
    while try needsDecodedData(minimum: minimum) {
      let encoded = if let pending = takeEncoded() {
        pending
      } else {
        try await nextSourceChunk(context: context)
      }
      if let encoded {
        try process(encoded)
      } else {
        try finishDecoder()
      }
    }
  }

  private func needsDecodedData(minimum: Int) throws -> Bool {
    try state.withLock { state in
      try checkOpenOrEOF(state)
      return state.decoded.count < minimum && !state.reachedEOD
    }
  }

  private func takeEncoded() -> Data? {
    state.withLock { state in
      guard !state.encoded.isEmpty else { return nil }
      let encoded = state.encoded
      state.encoded.removeAll()
      return encoded
    }
  }

  private func nextSourceChunkWithoutContext() throws -> Data? {
    switch sourceKind {
    case .file:
      return try sourceFile.file.read(max: 1)
    case .string:
      let shouldRead = state.withLock { state -> Bool in
        guard !state.stringConsumed else { return false }
        state.stringConsumed = true
        return true
      }
      let string = sourceString
      return shouldRead ? try string.characters(in: string.range) : nil
    case .procedure:
      throw Error.ioError
    }
  }

  private func nextSourceChunk(context: isolated Context) async throws -> Data? {
    switch sourceKind {
    case .file:
      return try await sourceFile.file.read(max: 1, context: context)
    case .string:
      return try nextSourceChunkWithoutContext()
    case .procedure:
      let procedure = source.object
      let originalDepth = context.operands.depth
      try await context.execute(proc: procedure)
      guard context.operands.depth == originalDepth + 1 else { throw Error.typeCheck }
      let string: StringValue = try context.operands.popAs()
      try string.access.check(.read)
      let data = try string.characters(in: string.range)
      return data.isEmpty ? nil : data
    }
  }

  private func process(_ input: Data) throws {
    let result = try translateCodecError { try codec.process(input: input) }
    guard result.consumedInput >= 0, result.consumedInput <= input.count else {
      throw Error.ioError
    }
    guard result.progress == .finished || result.consumedInput > 0 || !result.output.isEmpty else {
      throw Error.ioError
    }

    state.withLock { state in
      state.decoded.append(result.output)
      if result.progress == .finished {
        state.reachedEOD = true
        state.encoded.removeAll()
      } else if result.consumedInput < input.count {
        state.encoded.append(input.dropFirst(result.consumedInput))
      }
    }
  }

  private func finishDecoder() throws {
    let output = try translateCodecError { try codec.finish() ?? Data() }
    state.withLock { state in
      state.decoded.append(output)
      state.sourceEnded = true
      state.reachedEOD = true
    }
  }

  private func takeDecoded(max: Int) throws -> (data: Data?, close: Bool) {
    try state.withLock { state in
      try checkOpenOrEOF(state)
      guard !state.decoded.isEmpty else {
        return (nil, state.reachedEOD)
      }
      let count = min(max, state.decoded.count)
      let data = Data(state.decoded.prefix(count))
      state.decoded.removeFirst(count)
      return (data, state.reachedEOD && state.decoded.isEmpty)
    }
  }

  private func closeAfterEODWithoutContext() throws {
    let shouldCloseSource = state.withLock { state -> Bool in
      guard !state.closed, state.reachedEOD, state.decoded.isEmpty else { return false }
      state.closed = true
      return closeSource
    }
    if shouldCloseSource, sourceKind == .file {
      try sourceFile.file.close()
    }
  }

  private func closeAfterEOD(context: isolated Context) async throws {
    let shouldCloseSource = state.withLock { state -> Bool in
      guard !state.closed, state.reachedEOD, state.decoded.isEmpty else { return false }
      state.closed = true
      return closeSource
    }
    if shouldCloseSource, sourceKind == .file {
      try await sourceFile.file.close(context: context)
    }
  }

  private func checkOpenOrEOF(_ state: State) throws {
    if state.closed && !(state.reachedEOD && state.decoded.isEmpty) {
      throw Error.ioError
    }
  }

  var retainedVMAllocations: [VMAllocation] {
    source.allocation.map { [$0] } ?? []
  }

  func identifyRetainedEdges(source allocation: VMAllocation) {
    source.identifyEdgeSource(allocation)
  }

  private var sourceFile: FileValue {
    source.object.value as! FileValue
  }

  private var sourceString: StringValue {
    source.object.value as! StringValue
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

  private func withOperation<T>(_ body: () throws -> T) throws -> T {
    try beginOperation()
    defer { endOperation() }
    return try body()
  }

}
