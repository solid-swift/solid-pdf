//
//  FilteredFile.swift
//  SolidPostScript
//
//  Created by Codex on 8/15/26.
//

import Foundation
import SolidIO
import Synchronization

final class MaterializedFilterFile: File, Sendable {

  private struct State: Sendable {
    var data: Data
    var offset = 0
    var closed = false
  }

  let name: String
  let mode: Mode = .read
  let isPositionable: Bool
  var closesAtEndOfFile: Bool { closeAtEnd }
  private let closeAtEnd: Bool
  private let state: Mutex<State>

  init(data: Data, name: String, positionable: Bool, closeAtEnd: Bool) {
    self.name = name
    self.isPositionable = positionable
    self.closeAtEnd = closeAtEnd
    self.state = Mutex(State(data: data))
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

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    try state.withLock { state in
      if state.closed && closeAtEnd && state.offset == state.data.count {
        return (nil, true)
      }
      try checkOpen(state)
      guard state.offset < state.data.count else {
        if closeAtEnd { state.closed = true }
        return (nil, true)
      }
      let byte = state.data[state.offset]
      guard predicate(byte) else { return (nil, false) }
      state.offset += 1
      if closeAtEnd && state.offset == state.data.count { state.closed = true }
      return (byte, false)
    }
  }

  func read(max: Int) throws -> Data? {
    try state.withLock { state in
      if state.closed && closeAtEnd && state.offset == state.data.count {
        return nil
      }
      try checkOpen(state)
      guard max >= 0 else { throw Error.rangeCheck }
      guard state.offset < state.data.count else {
        if closeAtEnd { state.closed = true }
        return nil
      }
      let end = min(state.offset + max, state.data.count)
      let output = Data(state.data[state.offset..<end])
      state.offset = end
      if closeAtEnd && state.offset == state.data.count { state.closed = true }
      return output
    }
  }

  func write(contentsOf data: Data) throws {
    throw Error.ioError
  }

  func close() throws {
    state.withLock { $0.closed = true }
  }

  var offset: Int {
    get throws {
      guard isPositionable else { throw Error.ioError }
      return try state.withLock { state in
        try checkOpen(state)
        return state.offset
      }
    }
  }

  func setOffset(_ offset: Int) throws {
    guard isPositionable else { throw Error.ioError }
    try state.withLock { state in
      try checkOpen(state)
      guard offset >= 0, offset <= state.data.count else { throw Error.rangeCheck }
      state.offset = offset
    }
  }

  var available: Int {
    get throws {
      try state.withLock { state in
        try checkOpen(state)
        return state.data.count - state.offset
      }
    }
  }

  var size: Int {
    get throws {
      try state.withLock { state in
        try checkOpen(state)
        return state.data.count
      }
    }
  }

  func flush() throws {
    state.withLock { state in
      guard !state.closed else { return }
      state.offset = state.data.count
      if closeAtEnd { state.closed = true }
    }
  }

  func reset() throws {
    state.withLock { state in
      guard !state.closed, isPositionable else { return }
      state.offset = 0
    }
  }

  private func checkOpen(_ state: State) throws {
    guard !state.closed else { throw Error.ioError }
  }

}

final class EncodingFilterFile: ContextualFile, VMManagedFileGraph, Sendable {

  private struct State: Sendable {
    var closed = false
  }

  let name: String
  let mode: Mode = .write
  let isPositionable = false
  private let codec: any IncrementalFilter
  private let target: FilterTarget
  private let state = Mutex(State())

  init(name: String, codec: any IncrementalFilter, target: FilterTarget) {
    self.name = name
    self.codec = codec
    self.target = target
  }

  deinit {
    try? close()
  }

  var isClosed: Bool {
    state.withLock { $0.closed }
  }

  func readByte() throws -> UInt8? { throw Error.ioError }

  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool) {
    throw Error.ioError
  }

  func read(max: Int) throws -> Data? { throw Error.ioError }

  func write(contentsOf data: Data) throws {
    guard !isClosed else { throw Error.ioError }
    guard !target.requiresContext else { throw Error.ioError }
    let result = try translateCodecError { try codec.process(input: data) }
    try validate(result, inputCount: data.count)
    if result.progress == .finished {
      try target.finishWithoutContext(result.output)
      state.withLock { $0.closed = true }
    } else {
      try target.writeWithoutContext(result.output)
    }
  }

  func write(contentsOf data: Data, context: isolated Context) async throws {
    try checkOpen()
    try await target.initialize(context: context)
    let result = try translateCodecError { try codec.process(input: data) }
    try validate(result, inputCount: data.count)
    if result.progress == .finished {
      try await target.finish(result.output, context: context)
      state.withLock { $0.closed = true }
    } else {
      try await target.write(result.output, context: context)
    }
  }

  func close() throws {
    let wasOpen = state.withLock { state -> Bool in
      guard !state.closed else { return false }
      state.closed = true
      return true
    }
    if wasOpen {
      try target.closeWithoutContext()
    }
  }

  func close(context: isolated Context) async throws {
    guard state.withLock({ !$0.closed }) else { return }
    try await target.initialize(context: context)
    let output = try translateCodecError { try codec.finish() ?? Data() }
    try await target.finish(output, context: context)
    state.withLock { $0.closed = true }
  }

  var offset: Int { get throws { throw Error.ioError } }

  func setOffset(_ offset: Int) throws { throw Error.ioError }

  var available: Int { get throws { throw Error.ioError } }

  var size: Int { get throws { throw Error.ioError } }

  func flush() throws {
    guard !isClosed else { throw Error.ioError }
    guard !target.requiresContext else { throw Error.ioError }
    let output = try translateCodecError { try codec.flush() }
    try target.writeWithoutContext(output)
  }

  func flush(context: isolated Context) async throws {
    try checkOpen()
    try await target.initialize(context: context)
    let output = try translateCodecError { try codec.flush() }
    try await target.write(output, context: context)
    try await target.flush(context: context)
  }

  func reset() throws {}

  private func checkOpen() throws {
    guard !isClosed else { throw Error.ioError }
  }

  private func validate(_ result: IncrementalFilterResult, inputCount: Int) throws {
    guard result.consumedInput == inputCount else { throw Error.ioError }
  }

  var retainedVMAllocations: [VMAllocation] { target.retainedVMAllocations }

  func identifyRetainedEdges(source: VMAllocation) {
    target.identifyRetainedEdges(source: source)
  }

}

final class FilterTarget: Sendable {

  private enum DestinationKind: Sendable, Equatable {
    case file
    case string
    case procedure
  }

  private struct State: Sendable {
    var offset = 0
    var procedureBuffer: VMStoredObject?
    var sourceAllocation: VMAllocation?
    var initialized = false
    var finished = false
  }

  private let destination: VMStoredObject
  private let destinationKind: DestinationKind
  private let closeTarget: Bool
  private let state = Mutex(State())

  var requiresContext: Bool {
    destinationKind == .procedure
  }

  init(destination: Object, closeTarget: Bool) throws {
    switch destination.value {
    case let file as FileValue:
      try file.checkWritable()
      self.destinationKind = .file
    case let string as StringValue:
      try string.access.check(.write)
      self.destinationKind = .string
    default:
      try destination.checkProcedure()
      self.destinationKind = .procedure
    }
    self.destination = VMStoredObject(destination)
    self.closeTarget = closeTarget
  }

  func initialize(context: isolated Context) async throws {
    guard destinationKind == .procedure else { return }
    let procedure = destination.object
    guard state.withLock({ !$0.initialized }) else { return }
    let empty = Object.string(Data(), access: .unlimited, vm: .local, kind: .literal)
    let buffer = try await invoke(procedure, data: empty, more: true, context: context)
    guard buffer.count > 0 else { throw Error.rangeCheck }
    VMGraph.withLock {
      state.withLock { state in
        let stored = VMStoredObject(Object(value: buffer, kind: .literal))
        if let allocation = state.sourceAllocation {
          stored.identifyEdgeSource(allocation)
        }
        state.procedureBuffer = stored
        state.initialized = true
      }
    }
  }

  func writeWithoutContext(_ data: Data) throws {
    guard !data.isEmpty else { return }
    switch destinationKind {
    case .file:
      try destinationFile.file.write(contentsOf: data)
    case .string:
      try write(data, to: destinationString)
    case .procedure:
      throw Error.ioError
    }
  }

  func write(_ data: Data, context: isolated Context) async throws {
    guard !data.isEmpty else { return }
    switch destinationKind {
    case .file:
      try await destinationFile.file.write(contentsOf: data, context: context)
    case .string:
      try write(data, to: destinationString)
    case .procedure:
      try await write(data, to: destination.object, context: context)
    }
  }

  func flush(context: isolated Context) async throws {
    if destinationKind == .file {
      try await destinationFile.file.flush(context: context)
    }
  }

  func closeWithoutContext() throws {
    guard closeTarget, destinationKind == .file else { return }
    try destinationFile.file.close()
  }

  func finishWithoutContext(_ data: Data) throws {
    guard state.withLock({ !$0.finished }) else { return }
    try writeWithoutContext(data)
    if closeTarget, destinationKind == .file {
      try destinationFile.file.close()
    }
    guard destinationKind == .procedure else {
      state.withLock { $0.finished = true }
      return
    }
    throw Error.ioError
  }

  func finish(_ data: Data, context: isolated Context) async throws {
    guard state.withLock({ !$0.finished }) else { return }
    try await write(data, context: context)
    switch destinationKind {
    case .file:
      if closeTarget { try await destinationFile.file.close(context: context) }
    case .string:
      break
    case .procedure:
      let finalObject = try state.withLock { state -> Object in
        guard let stored = state.procedureBuffer,
          let buffer = stored.object.value as? StringValue
        else {
          throw Error.ioError
        }
        return try .string(sharing: buffer, subRange: 0..<UInt(state.offset), kind: .literal)
      }
      _ = try await invoke(destination.object, data: finalObject, more: false, context: context)
    }
    state.withLock { $0.finished = true }
  }

  private func write(_ data: Data, to string: StringValue) throws {
    try state.withLock { state in
      guard state.offset + data.count <= string.count else { throw Error.ioError }
      try string.updateCharacters(data, startingAt: UInt(state.offset))
      state.offset += data.count
    }
  }

  private func write(_ data: Data, to procedure: Object, context: isolated Context) async throws {
    var remaining = data
    while !remaining.isEmpty {
      let transfer = try state.withLock { state -> (StringValue, Int) in
        guard let stored = state.procedureBuffer,
          let buffer = stored.object.value as? StringValue
        else {
          throw Error.ioError
        }
        let count = min(remaining.count, Int(buffer.count) - state.offset)
        try buffer.updateCharacters(remaining.prefix(count), startingAt: UInt(state.offset))
        state.offset += count
        return (buffer, count)
      }
      remaining.removeFirst(transfer.1)

      let isFull = state.withLock { $0.offset == transfer.0.count }
      if isFull {
        let object = Object(value: transfer.0, kind: .literal)
        let next = try await invoke(procedure, data: object, more: true, context: context)
        guard next.count > 0 else { throw Error.rangeCheck }
        VMGraph.withLock {
          state.withLock { state in
            let stored = VMStoredObject(Object(value: next, kind: .literal))
            if let allocation = state.sourceAllocation {
              stored.identifyEdgeSource(allocation)
            }
            state.procedureBuffer = stored
            state.offset = 0
          }
        }
      }
    }
  }

  private func invoke(
    _ procedure: Object,
    data: Object,
    more: Bool,
    context: isolated Context
  ) async throws -> StringValue {
    let originalDepth = context.operands.depth
    try await context.execute(proc: procedure, ops: [.boolean(more), data])
    guard context.operands.depth == originalDepth + 1 else { throw Error.typeCheck }
    let result: StringValue = try context.operands.popAs()
    try result.access.check(.write)
    return result
  }

  var retainedVMAllocations: [VMAllocation] {
    var allocations = destination.allocation.map { [$0] } ?? []
    if let buffer = state.withLock({ $0.procedureBuffer?.allocation }) {
      allocations.append(buffer)
    }
    return allocations
  }

  func identifyRetainedEdges(source: VMAllocation) {
    VMGraph.withLock {
      destination.identifyEdgeSource(source)
      state.withLock { state in
        state.sourceAllocation = source
        state.procedureBuffer?.identifyEdgeSource(source)
      }
    }
  }

  private var destinationFile: FileValue {
    destination.object.value as! FileValue
  }

  private var destinationString: StringValue {
    destination.object.value as! StringValue
  }

}

func translateCodecError<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch StreamCodecError.limitExceeded {
    throw Error.limitCheck
  } catch is StreamCodecError {
    throw Error.ioError
  }
}

func translateCodecOption<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch StreamCodecError.invalidOption {
    throw Error.rangeCheck
  } catch StreamCodecError.limitExceeded {
    throw Error.limitCheck
  } catch is StreamCodecError {
    throw Error.ioError
  }
}
