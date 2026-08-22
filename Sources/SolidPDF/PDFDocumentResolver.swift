import Crypto
import Foundation
import SolidIO

actor PDFDocumentResolver<Session: PDFInputSourceSession> {
  nonisolated var parsingLimits: PDFParsingLimits { options.limits }
  private struct ResolutionKey: Sendable, Hashable {
    let reference: PDFObjectReference
    let revision: PDFRevisionIdentifier
  }

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
  private let openedSourceLength: Int64
  private var securityContext: PDFSecurityContext?
  private let streamRegistry = PDFDecodedStreamRegistry()
  private var objectCache = [ResolutionKey: PDFIndirectObject]()
  private var decodedObjectStreams = [ResolutionKey: DecodedObjectStream]()
  private var recency = [ResolutionKey]()
  private var cacheBytes = 0
  private var pending = [ResolutionKey: Task<PDFIndirectObject, Error>]()
  private var decodedStreamCache = [PDFStreamCacheKey: Data]()
  private var decodedStreamRecency = [PDFStreamCacheKey]()
  private var decodedStreamCacheBytes = 0
  private var pendingDecodedStreams = [PDFStreamCacheKey: Task<Data, Error>]()
  private var closed = false

  init(
    reader: PDFSourceReader<Session>,
    index: PDFCrossReferenceIndex,
    options: PDFParsingOptions,
    externalStreamProvider: (any PDFExternalStreamProvider)?,
    securityContext: PDFSecurityContext?,
    openedSourceLength: Int64
  ) {
    self.reader = reader
    self.index = index
    self.options = options
    self.externalStreamProvider = externalStreamProvider
    self.securityContext = securityContext
    self.openedSourceLength = openedSourceLength
  }

  func resolve(_ reference: PDFObjectReference) async throws -> PDFIndirectObject {
    try await resolve(reference, in: index.latestRevision.identifier, stack: [])
  }

  func resolve(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFIndirectObject {
    try await resolve(reference, in: revision, stack: [])
  }

  func readStream(_ stream: PDFStreamObject) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    return try await reader.read(stream.encodedRange)
  }

  func sourceBytes(in range: PDFSourceRange) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    return try await reader.read(range)
  }

  func sourceLength() async throws -> Int64 {
    guard !closed else { throw PDFParsingError.documentClosed }
    return try await reader.length()
  }

  func originalSourceData(maximumBytes: Int64) async throws -> Data {
    guard !closed else { throw PDFIncrementalUpdateError.documentClosed }
    let currentLength = try await reader.length()
    guard currentLength == openedSourceLength else { throw PDFIncrementalUpdateError.sourceChanged }
    guard currentLength >= 0,
      currentLength <= maximumBytes,
      currentLength <= Int64(Int.max)
    else { throw PDFIncrementalUpdateError.limitExceeded }
    return try await reader.read(try PDFSourceRange(offset: 0, length: Int(currentLength)))
  }

  func securityContextForWriting() throws -> PDFSecurityContext? {
    guard !closed else { throw PDFIncrementalUpdateError.documentClosed }
    return securityContext
  }

  func digest(
    of ranges: [PDFSourceRange],
    using algorithm: PDFDigestAlgorithm
  ) async throws -> Data {
    switch algorithm {
    case .sha1: return try await digest(of: ranges, using: Insecure.SHA1.self)
    case .sha256: return try await digest(of: ranges, using: SHA256.self)
    case .sha384: return try await digest(of: ranges, using: SHA384.self)
    case .sha512: return try await digest(of: ranges, using: SHA512.self)
    case .sha224, .unsupported:
      throw PDFParsingError.unsupported(
        .signatureAlgorithm(String(describing: algorithm)),
        .init(offset: 0, message: "The signature digest algorithm is unsupported.")
      )
    }
  }

  func materialize(
    ranges: [PDFSourceRange],
    maximumBytes: Int
  ) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    var result = Data()
    for range in ranges {
      let (size, overflow) = result.count.addingReportingOverflow(range.length)
      guard !overflow, size <= maximumBytes else {
        throw PDFParsingError.limitExceeded(.init(offset: range.offset, message: "Signed source material exceeds its scratch limit."))
      }
      result.append(try await reader.read(range))
    }
    return result
  }

  func changedObjectReferences(
    after revision: PDFRevisionIdentifier,
    through target: PDFRevisionIdentifier
  ) throws -> [PDFObjectReference] {
    guard let before = index.snapshots[revision], let after = index.snapshots[target] else {
      throw PDFParsingError.unknownRevision(revision)
    }
    let numbers = Set(before.keys).union(after.keys)
    return numbers.sorted().compactMap { number in
      guard before[number] != after[number], let entry = after[number] else { return nil }
      let generation: Int = switch entry.entry {
      case .free(_, let generation): generation
      case .uncompressed(_, let generation): generation
      case .compressed: 0
      }
      return PDFObjectReference(uncheckedObjectNumber: number, generationNumber: generation)
    }
  }

  func decodedStream(_ stream: PDFStreamObject) async throws -> PDFDecodedStream {
    guard !closed else { throw PDFParsingError.documentClosed }
    let key = PDFStreamCacheKey(stream, security: securityContext?.security)
    if stream.dictionary[PDFName("F")] == nil,
      let cached = decodedStreamCache[key]
    {
      touchDecodedStream(key)
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
    let key = PDFStreamCacheKey(stream, security: securityContext?.security)
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
    securityContext = nil
    await reader.close()
  }

  private func resolve(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier,
    stack: [ResolutionKey]
  ) async throws -> PDFIndirectObject {
    guard !closed else { throw PDFParsingError.documentClosed }
    try Task.checkCancellation()
    let key = ResolutionKey(reference: reference, revision: revision)
    if stack.contains(key) {
      throw PDFParsingError.referenceCycle((stack + [key]).map(\.reference))
    }
    if let cached = objectCache[key] {
      touch(key)
      return cached
    }
    if let task = pending[key] {
      return try await task.value
    }
    let nextStack = stack + [key]
    let task = Task<PDFIndirectObject, Error> {
      try await self.resolveUncached(reference, in: revision, stack: nextStack)
    }
    pending[key] = task
    do {
      let object = try await task.value
      pending[key] = nil
      insert(object, for: key)
      return object
    } catch {
      pending[key] = nil
      throw error
    }
  }

  private func digest<Hash: HashFunction>(
    of ranges: [PDFSourceRange],
    using _: Hash.Type
  ) async throws -> Data {
    guard !closed else { throw PDFParsingError.documentClosed }
    var hash = Hash()
    for range in ranges {
      var offset = range.offset
      while offset < range.endOffset {
        try Task.checkCancellation()
        let count = Int(min(Int64(64 * 1_024), range.endOffset - offset))
        let chunk = try await reader.read(PDFSourceRange(uncheckedOffset: offset, length: count))
        hash.update(data: chunk)
        offset += Int64(count)
      }
    }
    return Data(hash.finalize())
  }

  private func resolveUncached(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier,
    stack: [ResolutionKey]
  ) async throws -> PDFIndirectObject {
    try Task.checkCancellation()
    guard let indexed = try index.entry(for: reference.objectNumber, in: revision) else {
      throw PDFParsingError.unresolvedReference(reference)
    }
    switch indexed.entry {
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
        let lengthObject = try await self.resolve(lengthReference, in: revision, stack: stack)
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
      let rawValue: PDFObject
      if let securityContext,
        securityContext.encryptionReference != reference,
        !Self.isCrossReferenceDictionary(raw.value)
      {
        do {
          rawValue = try PDFObjectDecrypter.decrypt(raw.value, in: reference, using: securityContext)
        } catch {
          throw PDFParsingError.malformed(
            .init(offset: offset, object: reference, message: "An encrypted object is malformed.")
          )
        }
      } else {
        rawValue = raw.value
      }
      let value: PDFResolvedObject
      if let streamRange = raw.streamRange {
        guard case .dictionary(let dictionary) = rawValue else {
          throw PDFParsingError.malformed(
            .init(offset: offset, object: reference, message: "A stream lacks its dictionary.")
          )
        }
        value = .stream(
          PDFStreamObject(
            dictionary: dictionary,
            encodedRange: streamRange,
            objectReference: reference,
            revision: revision
          )
        )
      } else {
        value = .value(rawValue)
      }
      return PDFIndirectObject(
        reference: reference,
        value: value,
        sourceRange: raw.sourceRange,
        provenance: .file,
        definitionRevision: indexed.definitionRevision
      )
    case .compressed(let objectStreamNumber, let objectIndex):
      guard reference.generationNumber == 0 else {
        throw PDFParsingError.unresolvedReference(reference)
      }
      let containerReference = try referenceForObject(number: objectStreamNumber, in: revision)
      let decoded = try await decodedObjectStream(
        containerReference,
        in: revision,
        stack: stack
      )
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
          provenance: .objectStream(container: containerReference, index: objectIndex),
          definitionRevision: indexed.definitionRevision
        )
      } catch {
        await objectReader.close()
        throw error
      }
    }
  }

  private func decodedObjectStream(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier,
    stack: [ResolutionKey]
  ) async throws -> DecodedObjectStream {
    let key = ResolutionKey(reference: reference, revision: revision)
    if let cached = decodedObjectStreams[key] {
      touch(key)
      return cached
    }
    let container = try await resolve(reference, in: revision, stack: stack)
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
    let data = try await decodedBytes(stream)
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
      insertDecodedObjectStream(result, for: key)
      return result
    } catch {
      await headerReader.close()
      throw error
    }
  }

  private func referenceForObject(
    number: Int,
    in revision: PDFRevisionIdentifier
  ) throws -> PDFObjectReference {
    guard let indexed = try index.entry(for: number, in: revision) else {
      throw PDFParsingError.unresolvedReference(
        PDFObjectReference(uncheckedObjectNumber: number, generationNumber: 0)
      )
    }
    switch indexed.entry {
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

  private func insert(_ object: PDFIndirectObject, for key: ResolutionKey) {
    let size = estimatedFootprint(of: object)
    guard size <= options.limits.maximumCachedObjectBytes else { return }
    evict(untilAdding: size)
    objectCache[key] = object
    cacheBytes += size
    touch(key)
  }

  private func insertDecodedObjectStream(
    _ stream: DecodedObjectStream,
    for key: ResolutionKey
  ) {
    let size = stream.data.count + stream.objectNumbers.count * MemoryLayout<Int>.stride * 2
    guard size <= options.limits.maximumCachedObjectBytes else { return }
    evict(untilAdding: size)
    decodedObjectStreams[key] = stream
    cacheBytes += size
    touch(key)
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

  private func touch(_ key: ResolutionKey) {
    recency.removeAll { $0 == key }
    recency.append(key)
  }

  private func estimatedFootprint(of object: PDFIndirectObject) -> Int {
    if let sourceRange = object.sourceRange { return max(64, sourceRange.length) }
    return 256
  }

  private func makeDecodedStream(_ stream: PDFStreamObject) async throws -> PDFDecodedStream {
    let revision = stream.revision ?? index.latestRevision.identifier
    let configuration = try await PDFStreamConfiguration.resolve(
      stream: stream,
      options: options,
      resolve: { reference in
        let resolved = try await self.resolve(reference, in: revision)
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
    let filters = try decryptionFilters(for: configuration, stream: stream)
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
      filters: filters,
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

  private func decryptionFilters(
    for configuration: PDFStreamConfiguration,
    stream: PDFStreamObject
  ) throws -> [PDFStreamFilterSpecification] {
    var filters = configuration.filters
    if let cryptIndex = filters.firstIndex(where: { $0.name == PDFName("Crypt") }) {
      guard cryptIndex == 0 else {
        throw PDFParsingError.malformed(
          .init(
            offset: stream.encodedRange.offset,
            object: stream.objectReference,
            message: "Crypt must be the first stream filter."
          )
        )
      }
      let name: PDFName
      if let value = filters[0].parameters?["Name"] {
        guard case .name(let selectedName) = value else {
          throw PDFParsingError.malformed(
            .init(
              offset: stream.encodedRange.offset,
              object: stream.objectReference,
              message: "A Crypt filter Name must be a name."
            )
          )
        }
        name = selectedName
      } else {
        name = PDFName("Identity")
      }
      let implementation: any IncrementalFilter
      if name == PDFName("Identity") {
        implementation = PDFIdentityDecryptionFilter()
      } else {
        guard let securityContext, let reference = stream.objectReference else {
          throw PDFParsingError.unsupported(
            .encryptionFilter,
            .init(
              offset: stream.encodedRange.offset,
              object: stream.objectReference,
              message: "An explicit Crypt filter requires an authenticated document object."
            )
          )
        }
        implementation = try securityContext.explicitStreamFilter(named: name, object: reference)
      }
      filters[0] = PDFStreamFilterSpecification(
        name: PDFName("Crypt"),
        parameters: filters[0].parameters,
        implementation: implementation
      )
      return filters
    }

    guard configuration.fileSpecification == nil, let securityContext else { return filters }
    guard let reference = stream.objectReference else {
      throw PDFParsingError.malformed(
        .init(
          offset: stream.encodedRange.offset,
          message: "An encrypted embedded stream lacks indirect object identity."
        )
      )
    }
    let kind: PDFSecurityContext.StreamKind
    switch stream.dictionary.pdfName(named: "Type") {
    case PDFName("XRef"): kind = .crossReference
    case PDFName("Metadata"): kind = .metadata
    case PDFName("EmbeddedFile"): kind = .embeddedFile
    default: kind = .ordinary
    }
    guard let implementation = try securityContext.implicitStreamFilter(
      for: kind,
      object: reference
    ) else { return filters }
    filters.insert(
      PDFStreamFilterSpecification(
        name: PDFName("Crypt"),
        parameters: nil,
        implementation: implementation
      ),
      at: 0
    )
    return filters
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

  private static func isCrossReferenceDictionary(_ object: PDFObject) -> Bool {
    guard case .dictionary(let dictionary) = object else { return false }
    return dictionary.pdfName(named: "Type") == PDFName("XRef")
  }
}
