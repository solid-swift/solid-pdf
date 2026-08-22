import Foundation

actor PDFDocumentResolver<Session: PDFInputSourceSession> {
  private struct DecodedObjectStream: Sendable {
    let data: Data
    let objectNumbers: [Int]
    let offsets: [Int]
    let firstObjectOffset: Int
  }

  private let reader: PDFSourceReader<Session>
  private let index: PDFCrossReferenceIndex
  private let options: PDFParsingOptions
  private let externalStreamProvider: (any PDFExternalStreamProvider)?
  private let streamRegistry = PDFDecodedStreamRegistry()
  private var objectCache = [PDFObjectReference: PDFIndirectObject]()
  private var decodedObjectStreams = [PDFObjectReference: DecodedObjectStream]()
  private var recency = [PDFObjectReference]()
  private var cacheBytes = 0
  private var pending = [PDFObjectReference: Task<PDFIndirectObject, Error>]()
  private var decodedStreamCache = [PDFStreamCacheKey: Data]()
  private var decodedStreamRecency = [PDFStreamCacheKey]()
  private var decodedStreamCacheBytes = 0
  private var pendingDecodedStreams = [PDFStreamCacheKey: Task<Data, Error>]()
  private var closed = false

  init(
    reader: PDFSourceReader<Session>,
    index: PDFCrossReferenceIndex,
    options: PDFParsingOptions,
    externalStreamProvider: (any PDFExternalStreamProvider)?
  ) {
    self.reader = reader
    self.index = index
    self.options = options
    self.externalStreamProvider = externalStreamProvider
  }

  func resolve(_ reference: PDFObjectReference) async throws -> PDFIndirectObject {
    try await resolve(reference, stack: [])
  }

  func readStream(_ stream: PDFStreamObject) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    return try await reader.read(stream.encodedRange)
  }

  func decodedStream(_ stream: PDFStreamObject) async throws -> PDFDecodedStream {
    guard !closed else { throw PDFParsingError.documentClosed }
    if stream.dictionary[PDFName("F")] == nil,
      let cached = decodedStreamCache[PDFStreamCacheKey(stream)]
    {
      touchDecodedStream(PDFStreamCacheKey(stream))
      return PDFDecodedStream(
        state: PDFBufferedDecodedStreamState(
          data: cached,
          chunkByteCount: options.decodedStreamChunkByteCount
        )
      )
    }
    return try await makeDecodedStream(stream)
  }

  func decodedBytes(_ stream: PDFStreamObject) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    let cacheable = stream.dictionary[PDFName("F")] == nil
    let key = PDFStreamCacheKey(stream)
    if cacheable, let cached = decodedStreamCache[key] {
      touchDecodedStream(key)
      return cached
    }
    if cacheable, let task = pendingDecodedStreams[key] {
      return try await task.value
    }
    let task = Task<Data, Error> {
      let stream = try await self.makeDecodedStream(stream)
      var data = Data()
      do {
        for try await chunk in stream {
          data.append(chunk)
        }
        await stream.close()
        return data
      } catch {
        await stream.close()
        throw error
      }
    }
    if cacheable { pendingDecodedStreams[key] = task }
    do {
      let data = try await task.value
      if cacheable {
        pendingDecodedStreams[key] = nil
        insertDecodedStream(data, for: key)
      }
      return data
    } catch {
      if cacheable { pendingDecodedStreams[key] = nil }
      throw error
    }
  }

  func close() async {
    guard !closed else { return }
    closed = true
    for task in pending.values { task.cancel() }
    for task in pendingDecodedStreams.values { task.cancel() }
    pending.removeAll()
    pendingDecodedStreams.removeAll()
    objectCache.removeAll()
    decodedObjectStreams.removeAll()
    recency.removeAll()
    cacheBytes = 0
    decodedStreamCache.removeAll()
    decodedStreamRecency.removeAll()
    decodedStreamCacheBytes = 0
    await streamRegistry.closeAll()
    await reader.close()
  }

  private func resolve(
    _ reference: PDFObjectReference,
    stack: [PDFObjectReference]
  ) async throws -> PDFIndirectObject {
    guard !closed else { throw PDFParsingError.documentClosed }
    try Task.checkCancellation()
    if stack.contains(reference) {
      throw PDFParsingError.referenceCycle(stack + [reference])
    }
    if let cached = objectCache[reference] {
      touch(reference)
      return cached
    }
    if let task = pending[reference] {
      return try await task.value
    }
    let nextStack = stack + [reference]
    let task = Task<PDFIndirectObject, Error> {
      try await self.resolveUncached(reference, stack: nextStack)
    }
    pending[reference] = task
    do {
      let object = try await task.value
      pending[reference] = nil
      insert(object)
      return object
    } catch {
      pending[reference] = nil
      throw error
    }
  }

  private func resolveUncached(
    _ reference: PDFObjectReference,
    stack: [PDFObjectReference]
  ) async throws -> PDFIndirectObject {
    try Task.checkCancellation()
    guard let entry = index.entries[reference.objectNumber] else {
      throw PDFParsingError.unresolvedReference(reference)
    }
    switch entry {
    case .free:
      throw PDFParsingError.unresolvedReference(reference)
    case .uncompressed(let offset, let generation):
      guard generation == reference.generationNumber else {
        throw PDFParsingError.unresolvedReference(reference)
      }
      var parser = PDFObjectParser(
        reader: reader,
        position: offset,
        limits: options.limits,
        enclosingObject: reference
      )
      let raw = try await parser.parseRawIndirectObject { lengthReference in
        let lengthObject = try await self.resolve(lengthReference, stack: stack)
        guard case .value(.number(.integer(let length))) = lengthObject.value else {
          throw PDFParsingError.malformed(
            .init(
              offset: offset,
              object: reference,
              message: "An indirect stream Length must resolve to an integer."
            )
          )
        }
        return length
      }
      guard raw.reference == reference else {
        throw PDFParsingError.malformed(
          .init(
            offset: offset,
            object: reference,
            message: "The indirect object header does not match its cross-reference entry."
          )
        )
      }
      let value: PDFResolvedObject
      if let streamRange = raw.streamRange {
        guard case .dictionary(let dictionary) = raw.value else {
          throw PDFParsingError.malformed(
            .init(offset: offset, object: reference, message: "A stream lacks its dictionary.")
          )
        }
        value = .stream(
          PDFStreamObject(
            dictionary: dictionary,
            encodedRange: streamRange,
            objectReference: reference
          )
        )
      } else {
        value = .value(raw.value)
      }
      return PDFIndirectObject(
        reference: reference,
        value: value,
        sourceRange: raw.sourceRange,
        provenance: .file
      )
    case .compressed(let objectStreamNumber, let objectIndex):
      guard reference.generationNumber == 0 else {
        throw PDFParsingError.unresolvedReference(reference)
      }
      let containerReference = try referenceForObject(number: objectStreamNumber)
      let decoded = try await decodedObjectStream(containerReference, stack: stack)
      guard objectIndex >= 0, objectIndex < decoded.objectNumbers.count,
        decoded.objectNumbers[objectIndex] == reference.objectNumber
      else {
        throw PDFParsingError.malformed(
          .init(
            offset: 0,
            object: reference,
            message: "The object-stream index does not identify the requested object."
          )
        )
      }
      let relativeOffset = decoded.offsets[objectIndex]
      let start = try PDFCheckedArithmetic.add(
        decoded.firstObjectOffset,
        relativeOffset,
        offset: 0
      )
      let end: Int
      if objectIndex + 1 < decoded.offsets.count {
        end = try PDFCheckedArithmetic.add(
          decoded.firstObjectOffset,
          decoded.offsets[objectIndex + 1],
          offset: 0
        )
      } else {
        end = decoded.data.count
      }
      guard start >= decoded.firstObjectOffset, end >= start, end <= decoded.data.count else {
        throw PDFParsingError.malformed(
          .init(offset: 0, object: reference, message: "An object-stream offset is invalid.")
        )
      }
      let objectData = decoded.data.subdata(in: start..<end)
      let source = PDFDataInputSource(objectData)
      let session = try await source.makeSession()
      let objectOptions = PDFParsingOptions(
        limits: options.limits,
        sourceWindowByteCount: min(options.sourceWindowByteCount, max(1, objectData.count))
      )
      let objectReader = try await PDFSourceReader(session: session, options: objectOptions)
      do {
        var parser = PDFObjectParser(
          reader: objectReader,
          limits: options.limits,
          enclosingObject: reference
        )
        let value = try await parser.parseObject()
        try await parser.skipWhitespaceAndComments()
        guard parser.position == Int64(objectData.count) else {
          throw PDFParsingError.malformed(
            .init(offset: 0, object: reference, message: "An object-stream member has trailing tokens.")
          )
        }
        await objectReader.close()
        return PDFIndirectObject(
          reference: reference,
          value: .value(value),
          sourceRange: nil,
          provenance: .objectStream(container: containerReference, index: objectIndex)
        )
      } catch {
        await objectReader.close()
        throw error
      }
    }
  }

  private func decodedObjectStream(
    _ reference: PDFObjectReference,
    stack: [PDFObjectReference]
  ) async throws -> DecodedObjectStream {
    if let cached = decodedObjectStreams[reference] {
      touch(reference)
      return cached
    }
    let container = try await resolve(reference, stack: stack)
    guard case .stream(let stream) = container.value,
      stream.dictionary.pdfName(named: "Type") == PDFName("ObjStm"),
      let countValue = stream.dictionary.pdfInteger(named: "N"),
      let firstValue = stream.dictionary.pdfInteger(named: "First"),
      countValue >= 0,
      countValue <= Int64(options.limits.maximumObjectCount),
      firstValue >= 0,
      firstValue <= Int64(Int.max)
    else {
      throw PDFParsingError.malformed(
        .init(offset: 0, object: reference, message: "The compressed object container is invalid.")
      )
    }
    let encoded = try await reader.read(stream.encodedRange)
    let data = try PDFStructuralStreamDecoder.decode(
      encoded,
      dictionary: stream.dictionary,
      limits: options.limits,
      offset: stream.encodedRange.offset
    )
    let count = Int(countValue)
    let first = Int(firstValue)
    guard first <= data.count else {
      throw PDFParsingError.malformed(
        .init(offset: stream.encodedRange.offset, object: reference, message: "ObjStm First is invalid.")
      )
    }
    let headerSource = PDFDataInputSource(data)
    let headerSession = try await headerSource.makeSession()
    let headerOptions = PDFParsingOptions(
      limits: options.limits,
      sourceWindowByteCount: min(options.sourceWindowByteCount, max(1, data.count))
    )
    let headerReader = try await PDFSourceReader(session: headerSession, options: headerOptions)
    do {
      var parser = PDFObjectParser(reader: headerReader, limits: options.limits)
      var objectNumbers = [Int]()
      var offsets = [Int]()
      objectNumbers.reserveCapacity(count)
      offsets.reserveCapacity(count)
      for _ in 0..<count {
        try await parser.skipWhitespaceAndComments()
        let number = try await parser.parseUnsignedIntegerToken()
        try await parser.skipWhitespaceAndComments()
        let offset = try await parser.parseUnsignedIntegerToken()
        guard number > 0, number <= Int64(Int.max), offset <= Int64(Int.max) else {
          throw PDFParsingError.malformed(
            .init(offset: 0, object: reference, message: "An ObjStm header pair is invalid.")
          )
        }
        objectNumbers.append(Int(number))
        offsets.append(Int(offset))
      }
      guard parser.position <= Int64(first),
        Set(objectNumbers).count == objectNumbers.count,
        zip(offsets, offsets.dropFirst()).allSatisfy({ $0.0 < $0.1 }),
        offsets.first ?? 0 >= 0
      else {
        throw PDFParsingError.malformed(
          .init(offset: 0, object: reference, message: "The ObjStm header is inconsistent.")
        )
      }
      await headerReader.close()
      let result = DecodedObjectStream(
        data: data,
        objectNumbers: objectNumbers,
        offsets: offsets,
        firstObjectOffset: first
      )
      insertDecodedObjectStream(result, for: reference)
      return result
    } catch {
      await headerReader.close()
      throw error
    }
  }

  private func referenceForObject(number: Int) throws -> PDFObjectReference {
    guard let entry = index.entries[number] else {
      throw PDFParsingError.unresolvedReference(
        PDFObjectReference(uncheckedObjectNumber: number, generationNumber: 0)
      )
    }
    switch entry {
    case .uncompressed(_, let generation):
      return PDFObjectReference(uncheckedObjectNumber: number, generationNumber: generation)
    case .compressed:
      return PDFObjectReference(uncheckedObjectNumber: number, generationNumber: 0)
    case .free:
      throw PDFParsingError.unresolvedReference(
        PDFObjectReference(uncheckedObjectNumber: number, generationNumber: 0)
      )
    }
  }

  private func insert(_ object: PDFIndirectObject) {
    let size = estimatedFootprint(of: object)
    guard size <= options.limits.maximumCachedObjectBytes else { return }
    evict(untilAdding: size)
    objectCache[object.reference] = object
    cacheBytes += size
    touch(object.reference)
  }

  private func insertDecodedObjectStream(
    _ stream: DecodedObjectStream,
    for reference: PDFObjectReference
  ) {
    let size = stream.data.count + stream.objectNumbers.count * MemoryLayout<Int>.stride * 2
    guard size <= options.limits.maximumCachedObjectBytes else { return }
    evict(untilAdding: size)
    decodedObjectStreams[reference] = stream
    cacheBytes += size
    touch(reference)
  }

  private func evict(untilAdding size: Int) {
    while cacheBytes > options.limits.maximumCachedObjectBytes - size,
      let oldest = recency.first
    {
      recency.removeFirst()
      if let object = objectCache.removeValue(forKey: oldest) {
        cacheBytes -= estimatedFootprint(of: object)
      }
      if let stream = decodedObjectStreams.removeValue(forKey: oldest) {
        cacheBytes -= stream.data.count + stream.objectNumbers.count * MemoryLayout<Int>.stride * 2
      }
    }
  }

  private func touch(_ reference: PDFObjectReference) {
    recency.removeAll { $0 == reference }
    recency.append(reference)
  }

  private func estimatedFootprint(of object: PDFIndirectObject) -> Int {
    if let sourceRange = object.sourceRange { return max(64, sourceRange.length) }
    return 256
  }

  private func makeDecodedStream(_ stream: PDFStreamObject) async throws -> PDFDecodedStream {
    let configuration = try await PDFStreamConfiguration.resolve(
      stream: stream,
      options: options,
      resolve: { reference in
        let resolved = try await self.resolve(reference)
        guard case .value(let value) = resolved.value else {
          throw PDFParsingError.malformed(
            .init(
              offset: stream.encodedRange.offset,
              object: stream.objectReference,
              message: "A stream configuration reference resolves to a stream."
            )
          )
        }
        return value
      }
    )
    let input: PDFDecodedStreamInput
    if let fileSpecification = configuration.fileSpecification {
      guard let externalStreamProvider else {
        throw PDFParsingError.unsupported(
          .externalStream,
          .init(
            offset: stream.encodedRange.offset,
            object: stream.objectReference,
            message: "External stream access was not authorized."
          )
        )
      }
      do {
        let session = try await externalStreamProvider.open(fileSpecification, for: stream)
        input = try await PDFDecodedStreamInput(externalSession: session)
      } catch let error as PDFParsingError {
        throw error
      } catch {
        throw PDFParsingError.sourceFailure(
          .init(
            offset: stream.encodedRange.offset,
            object: stream.objectReference,
            message: "The external stream provider failed: \(error)"
          )
        )
      }
    } else {
      input = PDFDecodedStreamInput(reader: reader, range: stream.encodedRange)
    }
    let state = try PDFIncrementalDecodedStreamState(
      input: input,
      filters: configuration.filters,
      options: options,
      diagnostic: .init(
        offset: stream.encodedRange.offset,
        object: stream.objectReference,
        message: "The PDF stream could not be decoded."
      ),
      registry: streamRegistry
    )
    await state.register()
    return PDFDecodedStream(state: state)
  }

  private func insertDecodedStream(_ data: Data, for key: PDFStreamCacheKey) {
    let maximum = options.limits.maximumCachedDecodedStreamBytes
    guard data.count <= maximum else { return }
    while decodedStreamCacheBytes > maximum - data.count,
      let oldest = decodedStreamRecency.first
    {
      decodedStreamRecency.removeFirst()
      decodedStreamCacheBytes -= decodedStreamCache.removeValue(forKey: oldest)?.count ?? 0
    }
    decodedStreamCache[key] = data
    decodedStreamCacheBytes += data.count
    touchDecodedStream(key)
  }

  private func touchDecodedStream(_ key: PDFStreamCacheKey) {
    decodedStreamRecency.removeAll { $0 == key }
    decodedStreamRecency.append(key)
  }
}
