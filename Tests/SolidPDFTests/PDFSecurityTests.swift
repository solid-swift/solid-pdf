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

  private func encryptedFixture(
    revision: Int,
    userPassword: String = "user",
    ownerPassword: String = "owner"
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
        userPassword: userPassword,
        ownerPassword: ownerPassword,
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
    let filters = revision >= 4
      ? " /CF << /StdCF << /CFM /\(revision >= 5 ? "AESV3" : "AESV2") /Length \(revision >= 5 ? 32 : 16) >> >> /StmF /StdCF /StrF /StdCF /EncryptMetadata false"
      : ""
    let modern = revision >= 5
      ? " /OE <\(values.ownerEncryptedKey!.hex)> /UE <\(values.userEncryptedKey!.hex)> /Perms <\(values.permissions!.hex)>"
      : ""
    let encryptionDictionary = "<< /Filter /Standard    /V \(version) /R \(revision)\(length) /O <\(values.owner.hex)> /U <\(values.user.hex)>\(modern) /P -4\(filters) >>"

    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog >>\nendobj\n".utf8))
    let encryptionOffset = data.count
    data.append(Data("2 0 obj\n\(encryptionDictionary)\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 3\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", rootOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", encryptionOffset).utf8))
    data.append(
      Data(
        ("trailer\n<< /Size 3 /Root 1 0 R /Encrypt 2 0 R /ID [<\(identifier.hex)> <\(identifier.hex)>] >>\n"
          + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func replacing(_ data: Data, _ original: String, with replacement: String) -> Data {
    Data(
      String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: original, with: replacement).utf8
    )
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
        ("trailer\n<< /Size 3 /Root 1 0 R /Encrypt 2 0 R /Prev \(previousOffset) "
          + "/ID [<30313233343536373839616263646566> <30313233343536373839616263646566>] >>\n"
          + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
      )
    )
    return data
  }

  private func legacyValues(
    revision: Int,
    userPassword: String,
    ownerPassword: String,
    identifier: Data,
    permissions: UInt32
  ) throws -> SecurityValues {
    let keyByteCount = revision == 2 ? 5 : 16
    var ownerDigest = PDFCrypto.md5(padded(Data(ownerPassword.utf8)))
    if revision >= 3 {
      for _ in 0..<50 { ownerDigest = PDFCrypto.md5(ownerDigest) }
    }
    let ownerKey = ownerDigest.prefix(keyByteCount)
    var ownerValue = padded(Data(userPassword.utf8))
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
    var keyInput = padded(Data(userPassword.utf8))
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
    return SecurityValues(owner: ownerValue, user: userValue)
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
    var ownerEncryptedKey: Data?
    var userEncryptedKey: Data?
    var permissions: Data?
  }

  private static let padding = Data([
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ])
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
