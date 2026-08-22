import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFSecurityTests {
  @Test
  func validatesPublishedCipherAndDigestVectors() throws {
    #expect(
      try PDFRC4.process(Data("Plaintext".utf8), key: Data("Key".utf8)).hex
        == "bbf316e8d940af0ad3"
    )
    #expect(PDFCrypto.md5(Data()).hex == "d41d8cd98f00b204e9800998ecf8427e")
    #expect(
      PDFCrypto.sha256(Data("abc".utf8)).hex
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    let key = try Data(hex: "2b7e151628aed2a6abf7158809cf4f3c")
    let iv = try Data(hex: "000102030405060708090a0b0c0d0e0f")
    let plaintext = try Data(hex: "6bc1bee22e409f96e93d7e117393172a")
    let ciphertext = try Data(hex: "7649abac8119b246cee98e9b12e9197d")
    #expect(
      try PDFCrypto.aesCBCEncrypt(
        plaintext,
        key: key,
        initializationVector: iv,
        addsPadding: false
      ) == ciphertext
    )
    #expect(
      try PDFCrypto.aesCBCDecrypt(
        ciphertext,
        key: key,
        initializationVector: iv,
        removesPadding: false
      ) == plaintext
    )
    #expect(!PDFCrypto.constantTimeEqual(Data(), Data(repeating: 0, count: 256)))
  }

  @Test(arguments: [2, 3, 4, 5, 6])
  func authenticatesEveryStandardSecurityRevision(_ revision: Int) async throws {
    let fixture = try encryptedFixture(revision: revision)
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(fixture))
    }

    let userDocument = try await PDFDocument(
      source: PDFDataInputSource(fixture),
      password: PDFPassword(revision == 6 ? "I\u{00AD}X" : "user")
    )
    #expect(userDocument.security?.encryption.revision == revision)
    #expect(userDocument.security?.authentication == .user)
    #expect(userDocument.security?.rawPermissionFlags == UInt32(bitPattern: Int32(-4)))
    if revision == 2 {
      #expect(
        userDocument.security?.effectivePermissions
          == [.print, .modify, .extract, .annotate]
      )
    } else {
      #expect(userDocument.security?.effectivePermissions == .all)
    }
    await userDocument.close()

    let ownerDocument = try await PDFDocument(
      source: PDFDataInputSource(fixture),
      password: PDFPassword("owner")
    )
    #expect(ownerDocument.security?.authentication == .owner)
    #expect(ownerDocument.security?.effectivePermissions == .all)
    await ownerDocument.close()

    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture),
        password: PDFPassword("incorrect")
      )
    }
  }

  @Test
  func acceptsDefaultPasswordAndBoundsProviderAttempts() async throws {
    let defaultFixture = try encryptedFixture(revision: 2, userPassword: "")
    let defaultDocument = try await PDFDocument(source: PDFDataInputSource(defaultFixture))
    #expect(defaultDocument.security?.authentication == .defaultUser)
    await defaultDocument.close()

    let fixture = try encryptedFixture(revision: 4)
    let provider = SequencePasswordProvider([PDFPassword("wrong"), PDFPassword("user")])
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture),
      passwordProvider: provider
    )
    #expect(document.security?.authentication == .user)
    #expect(await provider.attempts == [1, 2])
    await document.close()

    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture),
        passwordProvider: FailingPasswordProvider()
      )
    }
    await #expect(throws: CancellationError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture),
        passwordProvider: CancellingPasswordProvider()
      )
    }
  }

  @Test
  func authenticatesAnExactByteLegacyPassword() async throws {
    let password = Data([0x80, 0xFF, 0x00, 0x41])
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        try encryptedFixture(revision: 2, exactUserPassword: password)
      ),
      password: PDFPassword(exactBytes: password)
    )
    #expect(document.security?.authentication == .user)
    await document.close()
  }

  @Test
  func appliesSASLprepMappingNormalizationAndProhibitions() throws {
    #expect(try PDFSASLprep.prepare("I\u{00AD}X") == Data("IX".utf8))
    #expect(try PDFSASLprep.prepare("\u{2168}") == Data("IX".utf8))
    #expect(throws: PDFParsingError.self) { try PDFSASLprep.prepare("bad\u{0007}") }
    #expect(throws: PDFParsingError.self) { try PDFSASLprep.prepare("\u{0221}") }
    #expect(throws: PDFParsingError.self) { try PDFSASLprep.prepare("\u{0627}a\u{0628}") }
  }

  @Test
  func rejectsUnsupportedHandlersAndIncrementalHandlerChanges() async throws {
    let fixture = try encryptedFixture(revision: 4)
    let publicKey = replacing(fixture, "/Standard    ", with: "/Adobe.PubSec")
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(publicKey))
    }
    let unpublished = replacing(fixture, "/V 4 /R 4", with: "/V 3 /R 4")
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(unpublished))
    }
    let unknownCrypt = replacing(fixture, "/CFM /AESV2", with: "/CFM /None  ")
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(unknownCrypt))
    }
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(incrementallyChangedEncryption(fixture))
      )
    }
  }

  @Test
  func passwordDescriptionsRemainRedacted() {
    let password = PDFPassword("never reveal this")
    #expect(password.description == "<redacted PDF password>")
    #expect(password.debugDescription == "<redacted PDF password>")
  }

  @Test(arguments: [2, 3, 4, 5, 6])
  func decryptsRecursiveStringsAndStreams(_ revision: Int) async throws {
    let fixture = try encryptedFixture(revision: revision)
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture),
      password: PDFPassword(revision == 6 ? "IX" : "user")
    )
    let stringReference = try PDFObjectReference(objectNumber: 3, generationNumber: 0)
    let stringObject = try await document.resolve(stringReference)
    guard case .value(.dictionary(let dictionary)) = stringObject.value,
      case .string(let literal) = dictionary["Literal"],
      case .array(let nested) = dictionary["Nested"],
      case .string(let nestedString) = nested.first,
      case .string(let escaped) = dictionary["Escaped"]
    else {
      Issue.record("Expected recursively decrypted strings")
      return
    }
    #expect(literal.bytes == Data("Secret text".utf8))
    #expect(nestedString.bytes == Data("Secret text".utf8))
    #expect(literal.representation == .hexadecimal)
    #expect(escaped.bytes == Data("Secret text".utf8))
    #expect(escaped.representation == .literal)

    let streamReference = try PDFObjectReference(objectNumber: 4, generationNumber: 0)
    guard case .stream(let stream) = try await document.resolve(streamReference).value else {
      Issue.record("Expected an encrypted stream")
      return
    }
    #expect(try await document.encodedBytes(of: stream) != Data("Stream secret".utf8))
    #expect(try await document.decodedBytes(of: stream) == Data("Stream secret".utf8))
    await document.close()
  }

  @Test(arguments: [StreamFixtureMode.explicit, .identity, .metadata, .embeddedIdentity])
  func appliesExplicitIdentityAndMetadataCryptRules(_ mode: StreamFixtureMode) async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(try encryptedFixture(revision: 4, streamMode: mode)),
      password: PDFPassword("user")
    )
    let reference = try PDFObjectReference(objectNumber: 4, generationNumber: 0)
    guard case .stream(let stream) = try await document.resolve(reference).value else {
      Issue.record("Expected a test stream")
      return
    }
    #expect(try await document.decodedBytes(of: stream) == Data("Stream secret".utf8))
    await document.close()
  }

  @Test
  func requiresCryptToBeTheFirstFilter() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        try encryptedFixture(revision: 4, streamMode: .misorderedCrypt)
      ),
      password: PDFPassword("user")
    )
    let reference = try PDFObjectReference(objectNumber: 4, generationNumber: 0)
    guard case .stream(let stream) = try await document.resolve(reference).value else {
      Issue.record("Expected a test stream")
      return
    }
    await #expect(throws: PDFParsingError.self) {
      _ = try await document.decodedBytes(of: stream)
    }
    await document.close()
  }

  @Test
  func appliesCryptFiltersToExternalStreamsWithoutImplicitDecryption() async throws {
    let identifier = Data("0123456789abcdef".utf8)
    let values = try legacyValues(
      revision: 4,
      userPassword: Data("user".utf8),
      ownerPassword: Data("owner".utf8),
      identifier: identifier,
      permissions: UInt32(bitPattern: -4)
    )
    let plaintext = Data("External stream secret".utf8)
    let ciphertext = try encryptObjectData(
      plaintext,
      revision: 4,
      fileKey: values.fileKey,
      objectNumber: 4
    )

    for (mode, externalBytes) in [
      (StreamFixtureMode.externalExplicit, ciphertext),
      (.externalPlain, plaintext),
    ] {
      let document = try await PDFDocument(
        source: PDFDataInputSource(try encryptedFixture(revision: 4, streamMode: mode)),
        externalStreamProvider: SecurityExternalStreamProvider(data: externalBytes),
        password: PDFPassword("user")
      )
      let reference = try PDFObjectReference(objectNumber: 4, generationNumber: 0)
      guard case .stream(let stream) = try await document.resolve(reference).value else {
        Issue.record("Expected an external test stream")
        return
      }
      #expect(try await document.decodedBytes(of: stream) == plaintext)
      await document.close()
    }
  }

  @Test(arguments: [4, 6])
  func rejectsInvalidAESCiphertextPadding(_ revision: Int) async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(
        try encryptedFixture(revision: revision, streamMode: .corruptCiphertext)
      ),
      password: PDFPassword(revision == 6 ? "IX" : "user")
    )
    let reference = try PDFObjectReference(objectNumber: 4, generationNumber: 0)
    guard case .stream(let stream) = try await document.resolve(reference).value else {
      Issue.record("Expected a corrupt encrypted stream")
      return
    }
    await #expect(throws: PDFParsingError.self) {
      _ = try await document.decodedBytes(of: stream)
    }
    await document.close()
  }

  @Test
  func rejectsTamperedModernPermissions() async throws {
    let fixture = try tamperingFirstHexDigit(
      after: "/Perms <",
      in: encryptedFixture(revision: 6)
    )
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture),
        password: PDFPassword("IX")
      )
    }
  }

  @Test
  func decryptsObjectStreamsExactlyOnce() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(try encryptedObjectStreamFixture()),
      password: PDFPassword("user")
    )
    let reference = try PDFObjectReference(objectNumber: 6, generationNumber: 0)
    let object = try await document.resolve(reference)
    guard case .value(.dictionary(let dictionary)) = object.value,
      case .string(let string) = dictionary["Secret"]
    else {
      Issue.record("Expected an object-stream string")
      return
    }
    #expect(string.bytes == Data("Inside object stream".utf8))
    #expect(
      object.provenance
        == .objectStream(
          container: try PDFObjectReference(objectNumber: 5, generationNumber: 0),
          index: 0
        )
    )
    await document.close()
  }

  @Test
  func decryptsHistoricalAndUpdatedObjectsInTheirSelectedRevision() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(try encryptedIncrementalFixture()),
      password: PDFPassword("user")
    )
    #expect(document.revisions.count == 2)
    let reference = try PDFObjectReference(objectNumber: 3, generationNumber: 0)
    let historical = try await document.resolve(reference, in: document.revisions[0].identifier)
    let latest = try await document.resolve(reference)
    #expect(decryptedLiteral(in: historical) == Data("Secret text".utf8))
    #expect(decryptedLiteral(in: latest) == Data("Updated secret".utf8))
    await document.close()
  }

  private func encryptedFixture(
    revision: Int,
    userPassword: String = "user",
    ownerPassword: String = "owner",
    exactUserPassword: Data? = nil,
    streamMode: StreamFixtureMode = .implicit
  ) throws -> Data {
    let identifier = Data("0123456789abcdef".utf8)
    let permissions = UInt32(bitPattern: -4)
    let values = try revision >= 5
      ? modernValues(
        revision: revision,
        userPassword: revision == 6 ? "IX" : userPassword,
        ownerPassword: ownerPassword,
        permissions: permissions
      )
      : legacyValues(
        revision: revision,
        userPassword: exactUserPassword ?? Data(userPassword.utf8),
        ownerPassword: Data(ownerPassword.utf8),
        identifier: identifier,
        permissions: permissions
      )
    let version = switch revision {
    case 2: 1
    case 3: 2
    case 4: 4
    default: 5
    }
    let length = revision == 2 ? "" : " /Length \(revision >= 5 ? 256 : 128)"
    let embeddedFileFilter = streamMode == .embeddedIdentity ? " /EFF /Identity" : ""
    let filters = revision >= 4
      ? " /CF << /StdCF << /CFM /\(revision >= 5 ? "AESV3" : "AESV2") /Length \(revision >= 5 ? 32 : 16) >> >> /StmF /StdCF /StrF /StdCF\(embeddedFileFilter) /EncryptMetadata false"
      : ""
    let modern = revision >= 5
      ? " /OE <\(values.ownerEncryptedKey!.hex)> /UE <\(values.userEncryptedKey!.hex)> /Perms <\(values.permissions!.hex)>"
      : ""
    let encryptionDictionary = "<< /Filter /Standard    /V \(version) /R \(revision)\(length) /O <\(values.owner.hex)> /U <\(values.user.hex)>\(modern) /P -4\(filters) >>"
    let encryptedString = try encryptObjectData(
      Data("Secret text".utf8),
      revision: revision,
      fileKey: values.fileKey,
      objectNumber: 3
    )
    let streamPlaintext = Data("Stream secret".utf8)
    let encryptedStream = try encryptObjectData(
      streamPlaintext,
      revision: revision,
      fileKey: values.fileKey,
      objectNumber: 4
    )
    let streamPayload: Data
    let streamEntries: String
    switch streamMode {
    case .implicit:
      streamPayload = encryptedStream
      streamEntries = ""
    case .explicit:
      streamPayload = encryptedStream
      streamEntries = "/Filter /Crypt /DecodeParms << /Name /StdCF >> "
    case .identity:
      streamPayload = streamPlaintext
      streamEntries = "/Filter /Crypt /DecodeParms << /Name /Identity >> "
    case .metadata:
      streamPayload = streamPlaintext
      streamEntries = "/Type /Metadata "
    case .embeddedIdentity:
      streamPayload = streamPlaintext
      streamEntries = "/Type /EmbeddedFile "
    case .misorderedCrypt:
      streamPayload = encryptedStream
      streamEntries = "/Filter [/ASCIIHexDecode /Crypt] /DecodeParms [null << /Name /StdCF >>] "
    case .externalExplicit:
      streamPayload = Data("ignored embedded data".utf8)
      streamEntries = "/F /External /FFilter /Crypt /FDecodeParms << /Name /StdCF >> "
    case .externalPlain:
      streamPayload = Data("ignored embedded data".utf8)
      streamEntries = "/F /External "
    case .corruptCiphertext:
      var corrupted = encryptedStream
      corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0x01
      streamPayload = corrupted
      streamEntries = ""
    }

    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Secret 3 0 R /Contents 4 0 R >>\nendobj\n".utf8))
    let encryptionOffset = data.count
    data.append(Data("2 0 obj\n\(encryptionDictionary)\nendobj\n".utf8))
    let stringOffset = data.count
    data.append(
      Data(
        ("3 0 obj\n<< /Literal <\(encryptedString.hex)> "
          + "/Nested [<\(encryptedString.hex)>] "
          + "/Escaped (\(octalLiteral(encryptedString))) >>\nendobj\n").utf8
      )
    )
    let streamOffset = data.count
    data.append(Data("4 0 obj\n<< \(streamEntries)/Length \(streamPayload.count) >>\nstream\n".utf8))
    data.append(streamPayload)
    data.append(Data("\nendstream\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", rootOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", encryptionOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", stringOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", streamOffset).utf8))
    data.append(
      Data(
        ("trailer\n<< /Size 5 /Root 1 0 R /Encrypt 2 0 R /ID [<\(identifier.hex)> <\(identifier.hex)>] >>\n"
          + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func encryptObjectData(
    _ plaintext: Data,
    revision: Int,
    fileKey: Data,
    objectNumber: Int
  ) throws -> Data {
    if revision >= 5 {
      let iv = Data(repeating: UInt8(objectNumber), count: 16)
      var result = iv
      result.append(
        try PDFCrypto.aesCBCEncrypt(
          plaintext,
          key: fileKey,
          initializationVector: iv,
          addsPadding: true
        )
      )
      return result
    }
    var keyInput = fileKey
    keyInput.append(contentsOf: [
      UInt8(objectNumber & 0xFF), UInt8((objectNumber >> 8) & 0xFF),
      UInt8((objectNumber >> 16) & 0xFF), 0, 0,
    ])
    if revision == 4 { keyInput.append(Data("sAlT".utf8)) }
    let objectKey = PDFCrypto.md5(keyInput).prefix(min(fileKey.count + 5, 16))
    if revision < 4 { return try PDFRC4.process(plaintext, key: objectKey) }
    let iv = Data(repeating: UInt8(objectNumber), count: 16)
    var result = iv
    result.append(
      try PDFCrypto.aesCBCEncrypt(
        plaintext,
        key: objectKey,
        initializationVector: iv,
        addsPadding: true
      )
    )
    return result
  }

  private func encryptedObjectStreamFixture() throws -> Data {
    let identifier = Data("0123456789abcdef".utf8)
    let permissions = UInt32(bitPattern: Int32(-4))
    let values = try legacyValues(
      revision: 4,
      userPassword: Data("user".utf8),
      ownerPassword: Data("owner".utf8),
      identifier: identifier,
      permissions: permissions
    )
    let encryptionDictionary = "<< /Filter /Standard /V 4 /R 4 /Length 128 /O <\(values.owner.hex)> /U <\(values.user.hex)> /P -4 /CF << /StdCF << /CFM /AESV2 /Length 16 >> >> /StmF /StdCF /StrF /StdCF /EncryptMetadata false >>"
    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Member 6 0 R >>\nendobj\n".utf8))
    let encryptionOffset = data.count
    data.append(Data("2 0 obj\n\(encryptionDictionary)\nendobj\n".utf8))
    let objectStreamOffset = data.count
    let decodedObjectStream = Data("6 0 << /Secret (Inside object stream) >>".utf8)
    let encodedObjectStream = try encryptObjectData(
      decodedObjectStream,
      revision: 4,
      fileKey: values.fileKey,
      objectNumber: 5
    )
    data.append(
      Data(
        ("5 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Length \(encodedObjectStream.count) >>\n"
          + "stream\n").utf8
      )
    )
    data.append(encodedObjectStream)
    data.append(Data("\nendstream\nendobj\n".utf8))
    let xrefOffset = data.count
    var entries = Data()
    appendEntry(type: 0, field2: 0, field3: 65_535, to: &entries)
    appendEntry(type: 1, field2: rootOffset, field3: 0, to: &entries)
    appendEntry(type: 1, field2: encryptionOffset, field3: 0, to: &entries)
    appendEntry(type: 0, field2: 0, field3: 0, to: &entries)
    appendEntry(type: 0, field2: 0, field3: 0, to: &entries)
    appendEntry(type: 1, field2: objectStreamOffset, field3: 0, to: &entries)
    appendEntry(type: 2, field2: 5, field3: 0, to: &entries)
    appendEntry(type: 1, field2: xrefOffset, field3: 0, to: &entries)
    data.append(
      Data(
        ("7 0 obj\n<< /Type /XRef /Size 8 /Root 1 0 R /Encrypt 2 0 R "
          + "/ID [<\(identifier.hex)> <\(identifier.hex)>] /W [1 4 2] "
          + "/Length \(entries.count) >>\nstream\n").utf8
      )
    )
    data.append(entries)
    data.append(Data("\nendstream\nendobj\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func encryptedIncrementalFixture() throws -> Data {
    let identifier = Data("0123456789abcdef".utf8)
    let permissions = UInt32(bitPattern: Int32(-4))
    let values = try legacyValues(
      revision: 4,
      userPassword: Data("user".utf8),
      ownerPassword: Data("owner".utf8),
      identifier: identifier,
      permissions: permissions
    )
    var data = try encryptedFixture(revision: 4)
    let previousOffset = terminalCrossReferenceOffset(in: data)
    let encrypted = try encryptObjectData(
      Data("Updated secret".utf8),
      revision: 4,
      fileKey: values.fileKey,
      objectNumber: 3
    )
    let objectOffset = data.count
    data.append(Data("3 0 obj\n<< /Literal <\(encrypted.hex)> >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n3 1\n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", objectOffset).utf8))
    data.append(
      Data(
        ("trailer\n<< /Size 5 /Root 1 0 R /Encrypt 2 0 R /Prev \(previousOffset) "
          + "/ID [<\(identifier.hex)> <\(identifier.hex)>] >>\n"
          + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func decryptedLiteral(in object: PDFIndirectObject) -> Data? {
    guard case .value(.dictionary(let dictionary)) = object.value,
      case .string(let string) = dictionary["Literal"]
    else { return nil }
    return string.bytes
  }

  private func terminalCrossReferenceOffset(in data: Data) -> Int {
    let text = String(decoding: data, as: UTF8.self)
    let markerRange = text.range(of: "startxref\n", options: .backwards)!
    let start = markerRange.upperBound
    let end = text[start...].firstIndex(of: "\n")!
    return Int(text[start..<end])!
  }

  private func appendEntry(type: UInt8, field2: Int, field3: Int, to data: inout Data) {
    data.append(type)
    data.append(UInt8((field2 >> 24) & 0xFF))
    data.append(UInt8((field2 >> 16) & 0xFF))
    data.append(UInt8((field2 >> 8) & 0xFF))
    data.append(UInt8(field2 & 0xFF))
    data.append(UInt8((field3 >> 8) & 0xFF))
    data.append(UInt8(field3 & 0xFF))
  }

  private func replacing(_ data: Data, _ original: String, with replacement: String) -> Data {
    var result = data
    guard let range = result.range(of: Data(original.utf8)) else { return result }
    result.replaceSubrange(range, with: Data(replacement.utf8))
    return result
  }

  private func tamperingFirstHexDigit(after marker: String, in data: Data) throws -> Data {
    var result = data
    guard let markerRange = result.range(of: Data(marker.utf8)), markerRange.upperBound < result.endIndex
    else { throw PDFParsingError.malformed(.init(offset: 0, message: "Fixture marker is absent.")) }
    let index = markerRange.upperBound
    result[index] = result[index] == 0x30 ? 0x31 : 0x30
    return result
  }

  private func octalLiteral(_ data: Data) -> String {
    data.map { String(format: "\\%03o", $0) }.joined()
  }

  private func incrementallyChangedEncryption(_ original: Data) -> Data {
    let text = String(decoding: original, as: UTF8.self)
    let marker = "startxref\n"
    let markerRange = text.range(of: marker, options: .backwards)!
    let offsetStart = markerRange.upperBound
    let offsetEnd = text[offsetStart...].firstIndex(of: "\n")!
    let previousOffset = Int(text[offsetStart..<offsetEnd])!
    var data = original
    let encryptionOffset = data.count
    data.append(Data("2 0 obj\n<< /Filter /Standard /V 1 /R 2 /O <00> /U <00> /P -4 >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n2 1\n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", encryptionOffset).utf8))
    data.append(
      Data(
        ("trailer\n<< /Size 5 /Root 1 0 R /Encrypt 2 0 R /Prev \(previousOffset) "
          + "/ID [<30313233343536373839616263646566> <30313233343536373839616263646566>] >>\n"
          + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func legacyValues(
    revision: Int,
    userPassword: Data,
    ownerPassword: Data,
    identifier: Data,
    permissions: UInt32
  ) throws -> SecurityValues {
    let keyByteCount = revision == 2 ? 5 : 16
    var ownerDigest = PDFCrypto.md5(padded(ownerPassword))
    if revision >= 3 {
      for _ in 0..<50 { ownerDigest = PDFCrypto.md5(ownerDigest) }
    }
    let ownerKey = ownerDigest.prefix(keyByteCount)
    var ownerValue = padded(userPassword)
    if revision == 2 {
      ownerValue = try PDFRC4.process(ownerValue, key: ownerKey)
    } else {
      for round in 0...19 {
        ownerValue = try PDFRC4.process(
          ownerValue,
          key: Data(ownerKey.map { $0 ^ UInt8(round) })
        )
      }
    }
    var keyInput = padded(userPassword)
    keyInput.append(ownerValue)
    keyInput.append(contentsOf: permissions.littleEndianBytes)
    keyInput.append(identifier)
    if revision >= 4 { keyInput.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) }
    var fileDigest = PDFCrypto.md5(keyInput)
    if revision >= 3 {
      for _ in 0..<50 { fileDigest = PDFCrypto.md5(fileDigest.prefix(keyByteCount)) }
    }
    let fileKey = fileDigest.prefix(keyByteCount)
    let userValue: Data
    if revision == 2 {
      userValue = try PDFRC4.process(Self.padding, key: fileKey)
    } else {
      var digestInput = Self.padding
      digestInput.append(identifier)
      var value = try PDFRC4.process(PDFCrypto.md5(digestInput), key: fileKey)
      for round in 1...19 {
        value = try PDFRC4.process(value, key: Data(fileKey.map { $0 ^ UInt8(round) }))
      }
      value.append(Data(repeating: 0, count: 16))
      userValue = value
    }
    return SecurityValues(owner: ownerValue, user: userValue, fileKey: fileKey)
  }

  private func modernValues(
    revision: Int,
    userPassword: String,
    ownerPassword: String,
    permissions: UInt32
  ) throws -> SecurityValues {
    let fileKey = Data((0..<32).map(UInt8.init))
    let userBytes = try PDFPasswordProcessing.bytes(PDFPassword(userPassword), revision: revision)
    let ownerBytes = try PDFPasswordProcessing.bytes(PDFPassword(ownerPassword), revision: revision)
    let userValidationSalt = Data("userVal1".utf8)
    let userKeySalt = Data("userKey1".utf8)
    let userHash = try modernHash(
      revision: revision,
      password: userBytes,
      salt: userValidationSalt,
      userKey: nil
    )
    var user = userHash
    user.append(userValidationSalt)
    user.append(userKeySalt)
    let userKey = try modernHash(
      revision: revision,
      password: userBytes,
      salt: userKeySalt,
      userKey: nil
    )
    let userEncryptedKey = try PDFCrypto.aesCBCEncrypt(
      fileKey,
      key: userKey,
      initializationVector: Data(repeating: 0, count: 16),
      addsPadding: false
    )

    let ownerValidationSalt = Data("ownrVal1".utf8)
    let ownerKeySalt = Data("ownrKey1".utf8)
    let ownerHash = try modernHash(
      revision: revision,
      password: ownerBytes,
      salt: ownerValidationSalt,
      userKey: user
    )
    var owner = ownerHash
    owner.append(ownerValidationSalt)
    owner.append(ownerKeySalt)
    let ownerKey = try modernHash(
      revision: revision,
      password: ownerBytes,
      salt: ownerKeySalt,
      userKey: user
    )
    let ownerEncryptedKey = try PDFCrypto.aesCBCEncrypt(
      fileKey,
      key: ownerKey,
      initializationVector: Data(repeating: 0, count: 16),
      addsPadding: false
    )
    var permissionBlock = Data(permissions.littleEndianBytes)
    permissionBlock.append(Data(repeating: 0xFF, count: 4))
    permissionBlock.append(0x46)
    permissionBlock.append(Data("adb".utf8))
    permissionBlock.append(Data(repeating: 0xA5, count: 4))
    let encryptedPermissions = try PDFCrypto.aesCBCEncrypt(
      permissionBlock,
      key: fileKey,
      initializationVector: Data(repeating: 0, count: 16),
      addsPadding: false
    )
    return SecurityValues(
      owner: owner,
      user: user,
      fileKey: fileKey,
      ownerEncryptedKey: ownerEncryptedKey,
      userEncryptedKey: userEncryptedKey,
      permissions: encryptedPermissions
    )
  }

  private func modernHash(
    revision: Int,
    password: Data,
    salt: Data,
    userKey: Data?
  ) throws -> Data {
    var input = password
    input.append(salt)
    if let userKey { input.append(userKey) }
    return revision == 5
      ? PDFCrypto.sha256(input)
      : try PDFSecurityContext.algorithm2B(input, password: password, userKey: userKey)
  }

  private func padded(_ password: Data) -> Data {
    var value = Data(password.prefix(32))
    if value.count < 32 { value.append(Self.padding.prefix(32 - value.count)) }
    return value
  }

  private struct SecurityValues {
    let owner: Data
    let user: Data
    let fileKey: Data
    var ownerEncryptedKey: Data?
    var userEncryptedKey: Data?
    var permissions: Data?
  }

  enum StreamFixtureMode: Sendable {
    case implicit
    case explicit
    case identity
    case metadata
    case embeddedIdentity
    case misorderedCrypt
    case externalExplicit
    case externalPlain
    case corruptCiphertext
  }

  private static let padding = Data([
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ])
}

private struct SecurityExternalStreamProvider: PDFExternalStreamProvider {
  let data: Data

  func open(
    _ fileSpecification: PDFObject,
    for stream: PDFStreamObject
  ) async throws -> any PDFInputSourceSession {
    SecurityExternalStreamSession(data: data)
  }
}

private actor SecurityExternalStreamSession: PDFInputSourceSession {
  let data: Data

  init(data: Data) {
    self.data = data
  }

  func length() async throws -> Int64 { Int64(data.count) }

  func read(_ range: PDFSourceRange) async throws -> Data {
    let lowerBound = Int(range.offset)
    return data.subdata(in: lowerBound..<(lowerBound + range.length))
  }

  func close() async {}
}

private actor SequencePasswordProvider: PDFPasswordProvider {
  private var passwords: [PDFPassword]
  private(set) var attempts = [Int]()

  init(_ passwords: [PDFPassword]) {
    self.passwords = passwords
  }

  func password(for request: PDFPasswordRequest) async throws -> PDFPassword? {
    attempts.append(request.attempt)
    return passwords.isEmpty ? nil : passwords.removeFirst()
  }
}

private struct FailingPasswordProvider: PDFPasswordProvider {
  struct Failure: Error {}

  func password(for request: PDFPasswordRequest) async throws -> PDFPassword? {
    throw Failure()
  }
}

private struct CancellingPasswordProvider: PDFPasswordProvider {
  func password(for request: PDFPasswordRequest) async throws -> PDFPassword? {
    throw CancellationError()
  }
}

extension Data {
  fileprivate init(hex: String) throws {
    guard hex.count.isMultiple(of: 2) else { throw HexError() }
    self.init()
    reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { throw HexError() }
      append(byte)
      index = next
    }
  }

  fileprivate var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension UInt32 {
  fileprivate var littleEndianBytes: [UInt8] {
    [
      UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF),
      UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF),
    ]
  }
}

private struct HexError: Error {}
