import Foundation
import SolidIO

struct PDFSecurityContext: Sendable {
  enum StreamKind: Equatable {
    case ordinary
    case embeddedFile
    case metadata
    case crossReference
  }
  struct AuthenticationResult: Sendable {
    let key: Data
    let kind: PDFAuthenticationKind
  }

  let security: PDFDocumentSecurity
  let fileKey: Data
  let encryptionReference: PDFObjectReference?
  let cryptFilters: [PDFName: PDFCryptFilterDescription]

  func decryptString(_ data: Data, in object: PDFObjectReference) throws -> Data {
    try decrypt(data, using: security.stringFilter, object: object)
  }

  func encryptObject(_ object: PDFObject, in reference: PDFObjectReference) throws -> PDFObject {
    switch object {
    case .string(let string):
      return .string(PDFString(
        bytes: try encrypt(string.bytes, using: security.stringFilter, object: reference),
        representation: .hexadecimal
      ))
    case .array(let values):
      return .array(try values.map { try encryptObject($0, in: reference) })
    case .dictionary(let dictionary):
      return .dictionary(try dictionary.mapValues { try encryptObject($0, in: reference) })
    default:
      return object
    }
  }

  func encryptStream(_ data: Data, in reference: PDFObjectReference) throws -> Data {
    try encrypt(data, using: security.streamFilter, object: reference)
  }

  func implicitStreamFilter(
    for kind: StreamKind,
    object: PDFObjectReference
  ) throws -> (any IncrementalFilter)? {
    if kind == .crossReference || kind == .metadata && !security.encryption.encryptsMetadata {
      return nil
    }
    let name = kind == .embeddedFile ? security.embeddedFileFilter : security.streamFilter
    guard name != PDFName("Identity") else { return nil }
    return try decryptionFilter(named: name, object: object)
  }

  func explicitStreamFilter(
    named name: PDFName,
    object: PDFObjectReference
  ) throws -> any IncrementalFilter {
    try decryptionFilter(named: name, object: object)
  }

  private func decrypt(
    _ data: Data,
    using filterName: PDFName,
    object: PDFObjectReference
  ) throws -> Data {
    let filter = try decryptionFilter(named: filterName, object: object)
    var output = Data()
    let result = try filter.process(input: data)
    output.append(result.output)
    output.append(try filter.finish() ?? Data())
    return output
  }

  private func encrypt(
    _ data: Data,
    using filterName: PDFName,
    object: PDFObjectReference
  ) throws -> Data {
    guard filterName != PDFName("Identity") else { return data }
    guard let description = cryptFilters[filterName] else {
      throw Self.malformed("An encryption crypt filter is undefined.")
    }
    switch description.method {
    case .identity:
      return data
    case .rc4:
      return try PDFRC4.process(
        data,
        key: objectKey(for: object, description: description, usesAESSalt: false)
      )
    case .aes128:
      return try aesEncrypt(
        data,
        key: objectKey(for: object, description: description, usesAESSalt: true)
      )
    case .aes256:
      return try aesEncrypt(data, key: fileKey)
    }
  }

  private func aesEncrypt(_ data: Data, key: Data) throws -> Data {
    var generator = SystemRandomNumberGenerator()
    let initializationVector = Data((0..<16).map { _ in
      UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
    })
    var result = initializationVector
    result.append(try PDFCrypto.aesCBCEncrypt(
      data,
      key: key,
      initializationVector: initializationVector,
      addsPadding: true
    ))
    return result
  }

  private func decryptionFilter(
    named name: PDFName,
    object: PDFObjectReference?
  ) throws -> any IncrementalFilter {
    if name == PDFName("Identity") { return PDFIdentityDecryptionFilter() }
    guard let description = cryptFilters[name] else {
      throw PDFParsingError.malformed(
        .init(offset: 0, object: object, message: "A crypt filter is undefined.")
      )
    }
    switch description.method {
    case .identity:
      return PDFIdentityDecryptionFilter()
    case .rc4:
      guard let object else {
        throw Self.malformed("RC4 string decryption lacks object identity.")
      }
      return try PDFRC4DecryptionFilter(
        key: objectKey(for: object, description: description, usesAESSalt: false)
      )
    case .aes128:
      guard let object else {
        throw Self.malformed("AES string decryption lacks object identity.")
      }
      return PDFAESDecryptionFilter(
        key: objectKey(for: object, description: description, usesAESSalt: true)
      )
    case .aes256:
      return PDFAESDecryptionFilter(key: fileKey)
    }
  }

  private func objectKey(
    for object: PDFObjectReference,
    description: PDFCryptFilterDescription,
    usesAESSalt: Bool
  ) -> Data {
    var input = Data(fileKey.prefix(description.keyByteCount))
    input.append(contentsOf: [
      UInt8(object.objectNumber & 0xFF),
      UInt8((object.objectNumber >> 8) & 0xFF),
      UInt8((object.objectNumber >> 16) & 0xFF),
      UInt8(object.generationNumber & 0xFF),
      UInt8((object.generationNumber >> 8) & 0xFF),
    ])
    if usesAESSalt { input.append(Data("sAlT".utf8)) }
    return PDFCrypto.md5(input).prefix(min(description.keyByteCount + 5, 16))
  }

  private static let passwordPadding = Data([
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ])

  static func open<Session: PDFInputSourceSession>(
    reader: PDFSourceReader<Session>,
    index: PDFCrossReferenceIndex,
    options: PDFParsingOptions,
    passwordProvider: (any PDFPasswordProvider)?
  ) async throws -> PDFSecurityContext? {
    guard let encryptionObject = index.revisions[0].encryptionObject else { return nil }
    let located = try await locateEncryptionDictionary(
      encryptionObject,
      reader: reader,
      index: index,
      revision: index.revisions[0].identifier,
      limits: options.limits
    )
    for revision in index.revisions.dropFirst() {
      guard let object = revision.encryptionObject else {
        throw malformed("An incremental update removed the document security handler.")
      }
      let updated = try await locateEncryptionDictionary(
        object,
        reader: reader,
        index: index,
        revision: revision.identifier,
        limits: options.limits
      )
      guard updated.dictionary == located.dictionary else {
        throw malformed("An incremental update changed the document security handler.")
      }
    }
    let configuration = try Configuration(
      dictionary: located.dictionary,
      identifier: index.revisions[0].fileIdentifier?.first?.bytes,
      limits: options.limits
    )
    let description = configuration.description

    if let result = try configuration.authenticate(PDFPassword(exactBytes: Data())) {
      return configuration.context(
        result: .init(key: result.key, kind: .defaultUser),
        encryptionReference: located.reference
      )
    }
    guard let passwordProvider else {
      throw PDFParsingError.authenticationRequired(description)
    }
    guard options.limits.maximumPasswordAttempts > 0 else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "The configured password-attempt limit is zero.")
      )
    }
    for attempt in 1...options.limits.maximumPasswordAttempts {
      let candidate: PDFPassword?
      do {
        candidate = try await passwordProvider.password(
          for: PDFPasswordRequest(attempt: attempt, encryption: description)
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw PDFParsingError.authenticationFailure(
          .init(offset: 0, message: "The PDF password provider failed.")
        )
      }
      guard let candidate else { throw PDFParsingError.invalidPassword(description) }
      if let result = try configuration.authenticate(candidate) {
        return configuration.context(result: result, encryptionReference: located.reference)
      }
    }
    throw PDFParsingError.invalidPassword(description)
  }

  private static func locateEncryptionDictionary<Session: PDFInputSourceSession>(
    _ object: PDFObject,
    reader: PDFSourceReader<Session>,
    index: PDFCrossReferenceIndex,
    revision: PDFRevisionIdentifier,
    limits: PDFParsingLimits
  ) async throws -> (dictionary: [PDFName: PDFObject], reference: PDFObjectReference?) {
    switch object {
    case .dictionary(let dictionary):
      return (dictionary, nil)
    case .reference(let reference):
      guard let indexed = try index.entry(
        for: reference.objectNumber,
        in: revision
      ) else {
        throw malformed("The encryption dictionary reference is unresolved.")
      }
      guard case .uncompressed(let offset, let generation) = indexed.entry,
        generation == reference.generationNumber
      else {
        throw malformed("An encryption dictionary must be an uncompressed indirect object.")
      }
      var parser = PDFObjectParser(
        reader: reader,
        position: offset,
        limits: limits,
        enclosingObject: reference
      )
      let raw = try await parser.parseRawIndirectObject()
      guard raw.reference == reference, raw.streamRange == nil,
        case .dictionary(let dictionary) = raw.value
      else {
        throw malformed("The encryption object is not an ordinary dictionary.")
      }
      return (dictionary, reference)
    case .name(let name) where name == PDFName("Adobe.PubSec"):
      throw PDFParsingError.unsupported(
        .publicKeySecurity,
        .init(offset: 0, message: "Public-key PDF security is not supported.")
      )
    default:
      throw malformed("The Encrypt trailer entry is invalid.")
    }
  }

  private static func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  static func algorithm2B(
    _ initialInput: Data,
    password: Data,
    userKey: Data?,
    maximumScratchBytes: Int = 1 * 1_024 * 1_024
  ) throws -> Data {
    var key = PDFCrypto.sha256(initialInput)
    var round = 0
    while true {
      var block = password
      block.append(key)
      if let userKey { block.append(userKey) }
      let repeatedByteCount = try PDFCheckedArithmetic.multiply(block.count, 64, offset: 0)
      guard repeatedByteCount <= maximumScratchBytes else {
        throw PDFParsingError.limitExceeded(
          .init(offset: 0, message: "R6 password hashing exceeded security scratch storage.")
        )
      }
      var repeated = Data(capacity: repeatedByteCount)
      for _ in 0..<64 { repeated.append(block) }
      let encrypted = try PDFCrypto.aesCBCEncrypt(
        repeated,
        key: key.prefix(16),
        initializationVector: key.subdata(in: 16..<32),
        addsPadding: false
      )
      let selector = encrypted.prefix(16).reduce(0) { ($0 + Int($1)) % 3 }
      key = switch selector {
      case 0: PDFCrypto.sha256(encrypted)
      case 1: PDFCrypto.sha384(encrypted)
      default: PDFCrypto.sha512(encrypted)
      }
      round += 1
      if round >= 64, Int(encrypted.last ?? 0) <= round - 32 { return key.prefix(32) }
      guard round < 288 else {
        throw malformed("R6 password hashing exceeded its bounded rounds.")
      }
    }
  }

  private struct Configuration {
    let version: Int
    let revision: Int
    let keyByteCount: Int
    let owner: Data
    let user: Data
    let ownerEncryptedKey: Data?
    let userEncryptedKey: Data?
    let encryptedPermissions: Data?
    let rawPermissions: UInt32
    let identifier: Data?
    let encryptsMetadata: Bool
    let cryptFilters: [PDFName: PDFCryptFilterDescription]
    let streamFilter: PDFName
    let stringFilter: PDFName
    let embeddedFileFilter: PDFName
    let maximumScratchBytes: Int

    var description: PDFEncryptionDescription {
      PDFEncryptionDescription(
        version: version,
        revision: revision,
        keyBitCount: keyByteCount * 8,
        encryptsMetadata: encryptsMetadata,
        cryptFilters: cryptFilters.values.sorted { $0.name < $1.name }
      )
    }

    init(
      dictionary: [PDFName: PDFObject],
      identifier: Data?,
      limits: PDFParsingLimits
    ) throws {
      guard let filter = dictionary.pdfName(named: "Filter") else {
        throw PDFSecurityContext.malformed("The encryption dictionary lacks Filter.")
      }
      guard filter == PDFName("Standard") else {
        if filter == PDFName("Adobe.PubSec") {
          throw PDFParsingError.unsupported(
            .publicKeySecurity,
            .init(offset: 0, message: "Public-key PDF security is not supported.")
          )
        }
        throw PDFParsingError.unsupported(
          .securityHandler(filter),
          .init(offset: 0, message: "The PDF security handler is unsupported.")
        )
      }
      guard let versionValue = dictionary.pdfInteger(named: "V"),
        let revisionValue = dictionary.pdfInteger(named: "R"),
        (1...5).contains(versionValue), (2...6).contains(revisionValue)
      else { throw PDFSecurityContext.malformed("The Standard security version is invalid.") }
      guard versionValue != 3 else {
        throw PDFParsingError.unsupported(
          .unpublishedEncryptionAlgorithm,
          .init(offset: 0, message: "PDF encryption algorithm V3 was never published.")
        )
      }
      version = Int(versionValue)
      revision = Int(revisionValue)
      guard Self.isValidCombination(version: version, revision: revision) else {
        throw PDFSecurityContext.malformed("The Standard security V and R values are inconsistent.")
      }
      keyByteCount = try Self.keyByteCount(dictionary, version: version, revision: revision)
      owner = try Self.requiredString(dictionary, name: "O")
      user = try Self.requiredString(dictionary, name: "U")
      guard let permissions = dictionary.pdfInteger(named: "P"),
        permissions >= Int64(Int32.min), permissions <= Int64(UInt32.max)
      else { throw PDFSecurityContext.malformed("The Standard security P value is invalid.") }
      rawPermissions = UInt32(truncatingIfNeeded: permissions)
      encryptsMetadata = try Self.boolean(dictionary, name: "EncryptMetadata", default: true)
      maximumScratchBytes = limits.maximumSecurityScratchBytes
      self.identifier = identifier

      if revision >= 5 {
        guard owner.count == 48, user.count == 48 else {
          throw PDFSecurityContext.malformed("R5 and R6 O and U values must be 48 bytes.")
        }
        ownerEncryptedKey = try Self.requiredString(dictionary, name: "OE", count: 32)
        userEncryptedKey = try Self.requiredString(dictionary, name: "UE", count: 32)
        encryptedPermissions = try Self.requiredString(dictionary, name: "Perms", count: 16)
      } else {
        guard owner.count == 32, user.count >= 32 else {
          throw PDFSecurityContext.malformed("A legacy O or U value has an invalid length.")
        }
        guard identifier != nil else {
          throw PDFSecurityContext.malformed("Legacy encryption requires a document identifier.")
        }
        ownerEncryptedKey = nil
        userEncryptedKey = nil
        encryptedPermissions = nil
      }

      let parsedFilters = try Self.cryptFilters(
        dictionary,
        version: version,
        keyByteCount: keyByteCount,
        maximumCount: limits.maximumCryptFilters
      )
      cryptFilters = parsedFilters
      if version >= 4 {
        streamFilter = dictionary.pdfName(named: "StmF") ?? PDFName("Identity")
        stringFilter = dictionary.pdfName(named: "StrF") ?? PDFName("Identity")
        embeddedFileFilter = dictionary.pdfName(named: "EFF") ?? streamFilter
      } else {
        streamFilter = PDFName("StdCF")
        stringFilter = PDFName("StdCF")
        embeddedFileFilter = PDFName("StdCF")
      }
      try Self.validate(filter: streamFilter, in: parsedFilters)
      try Self.validate(filter: stringFilter, in: parsedFilters)
      try Self.validate(filter: embeddedFileFilter, in: parsedFilters)
    }

    func authenticate(_ password: PDFPassword) throws -> AuthenticationResult? {
      let bytes = try PDFPasswordProcessing.bytes(password, revision: revision)
      if revision >= 5 { return try authenticateModern(bytes) }
      return try authenticateLegacy(bytes)
    }

    func context(
      result: AuthenticationResult,
      encryptionReference: PDFObjectReference?
    ) -> PDFSecurityContext {
      let revisionPermissions: PDFPermissionSet = revision == 2
        ? [.print, .modify, .extract, .annotate]
        : .all
      let effectivePermissions: PDFPermissionSet = result.kind == .owner
        ? .all
        : PDFPermissionSet(rawValue: rawPermissions & revisionPermissions.rawValue)
      return PDFSecurityContext(
        security: PDFDocumentSecurity(
          encryption: description,
          authentication: result.kind,
          rawPermissionFlags: rawPermissions,
          effectivePermissions: effectivePermissions,
          streamFilter: streamFilter,
          stringFilter: stringFilter,
          embeddedFileFilter: embeddedFileFilter
        ),
        fileKey: result.key,
        encryptionReference: encryptionReference,
        cryptFilters: cryptFilters
      )
    }

    private func authenticateLegacy(_ password: Data) throws -> AuthenticationResult? {
      let userKey = legacyFileKey(password)
      if try validatesLegacyUserKey(userKey) {
        return .init(key: userKey, kind: .user)
      }
      let recovered = try recoverLegacyUserPassword(from: password)
      let ownerKey = legacyFileKey(recovered)
      if try validatesLegacyUserKey(ownerKey) {
        return .init(key: ownerKey, kind: .owner)
      }
      return nil
    }

    private func authenticateModern(_ password: Data) throws -> AuthenticationResult? {
      let userValidation = try modernHash(password, salt: user.subdata(in: 32..<40), userKey: nil)
      if PDFCrypto.constantTimeEqual(userValidation, user.prefix(32)) {
        let keyHash = try modernHash(password, salt: user.subdata(in: 40..<48), userKey: nil)
        let key = try decryptModernKey(userEncryptedKey!, with: keyHash)
        try validatePermissions(key)
        return .init(key: key, kind: .user)
      }
      let ownerValidation = try modernHash(
        password,
        salt: owner.subdata(in: 32..<40),
        userKey: user
      )
      if PDFCrypto.constantTimeEqual(ownerValidation, owner.prefix(32)) {
        let keyHash = try modernHash(password, salt: owner.subdata(in: 40..<48), userKey: user)
        let key = try decryptModernKey(ownerEncryptedKey!, with: keyHash)
        try validatePermissions(key)
        return .init(key: key, kind: .owner)
      }
      return nil
    }

    private func modernHash(_ password: Data, salt: Data, userKey: Data?) throws -> Data {
      var input = password
      input.append(salt)
      if let userKey { input.append(userKey) }
      return revision == 5
        ? PDFCrypto.sha256(input)
        : try PDFSecurityContext.algorithm2B(
          input,
          password: password,
          userKey: userKey,
          maximumScratchBytes: maximumScratchBytes
        )
    }

    private func decryptModernKey(_ encrypted: Data, with hash: Data) throws -> Data {
      do {
        return try PDFCrypto.aesCBCDecrypt(
          encrypted,
          key: hash.prefix(32),
          initializationVector: Data(repeating: 0, count: 16),
          removesPadding: false
        )
      } catch {
        throw PDFSecurityContext.malformed("An encrypted file key is malformed.")
      }
    }

    private func validatePermissions(_ key: Data) throws {
      guard let encryptedPermissions else { return }
      let plaintext: Data
      do {
        plaintext = try PDFCrypto.aesECBDecryptBlock(encryptedPermissions, key: key)
      } catch {
        throw PDFSecurityContext.malformed("The encrypted permissions block is malformed.")
      }
      let expected = Data([
        UInt8(rawPermissions & 0xFF),
        UInt8((rawPermissions >> 8) & 0xFF),
        UInt8((rawPermissions >> 16) & 0xFF),
        UInt8((rawPermissions >> 24) & 0xFF),
      ])
      guard PDFCrypto.constantTimeEqual(plaintext.prefix(4), expected),
        plaintext.subdata(in: 4..<8) == Data(repeating: 0xFF, count: 4),
        plaintext[8] == (encryptsMetadata ? 0x54 : 0x46),
        plaintext.subdata(in: 9..<12) == Data("adb".utf8)
      else { throw PDFSecurityContext.malformed("The encrypted permissions block is invalid.") }
    }

    private func legacyFileKey(_ password: Data) -> Data {
      var input = Self.paddedLegacyPassword(password)
      input.append(owner)
      input.append(contentsOf: [
        UInt8(rawPermissions & 0xFF),
        UInt8((rawPermissions >> 8) & 0xFF),
        UInt8((rawPermissions >> 16) & 0xFF),
        UInt8((rawPermissions >> 24) & 0xFF),
      ])
      input.append(identifier!)
      if revision >= 4, !encryptsMetadata { input.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) }
      var digest = PDFCrypto.md5(input)
      if revision >= 3 {
        for _ in 0..<50 { digest = PDFCrypto.md5(digest.prefix(keyByteCount)) }
      }
      return digest.prefix(keyByteCount)
    }

    private func validatesLegacyUserKey(_ key: Data) throws -> Bool {
      if revision == 2 {
        return PDFCrypto.constantTimeEqual(
          try PDFRC4.process(PDFSecurityContext.passwordPadding, key: key),
          user.prefix(32)
        )
      }
      var digestInput = PDFSecurityContext.passwordPadding
      digestInput.append(identifier!)
      var value = try PDFRC4.process(PDFCrypto.md5(digestInput), key: key)
      for round in 1...19 {
        value = try PDFRC4.process(value, key: Self.xor(key, with: UInt8(round)))
      }
      return PDFCrypto.constantTimeEqual(value.prefix(16), user.prefix(16))
    }

    private func recoverLegacyUserPassword(from ownerPassword: Data) throws -> Data {
      var digest = PDFCrypto.md5(Self.paddedLegacyPassword(ownerPassword))
      if revision >= 3 {
        for _ in 0..<50 { digest = PDFCrypto.md5(digest) }
      }
      let ownerKey = digest.prefix(keyByteCount)
      var value = owner
      if revision == 2 { return try PDFRC4.process(value, key: ownerKey) }
      for round in stride(from: 19, through: 0, by: -1) {
        value = try PDFRC4.process(value, key: Self.xor(ownerKey, with: UInt8(round)))
      }
      return value
    }

    private static func paddedLegacyPassword(_ password: Data) -> Data {
      var result = Data(password.prefix(32))
      if result.count < 32 {
        result.append(PDFSecurityContext.passwordPadding.prefix(32 - result.count))
      }
      return result
    }

    private static func xor(_ data: Data, with byte: UInt8) -> Data {
      Data(data.map { $0 ^ byte })
    }

    private static func isValidCombination(version: Int, revision: Int) -> Bool {
      switch revision {
      case 2: version == 1
      case 3: version == 2
      case 4: version == 4
      case 5, 6: version == 5
      default: false
      }
    }

    private static func keyByteCount(
      _ dictionary: [PDFName: PDFObject],
      version: Int,
      revision: Int
    ) throws -> Int {
      if revision == 2 {
        guard dictionary["Length"] == nil || dictionary.pdfInteger(named: "Length") == 40 else {
          throw PDFSecurityContext.malformed("R2 requires a 40-bit file key.")
        }
        return 5
      }
      if revision >= 5 {
        guard dictionary["Length"] == nil || dictionary.pdfInteger(named: "Length") == 256 else {
          throw PDFSecurityContext.malformed("R5 and R6 require a 256-bit file key.")
        }
        return 32
      }
      if dictionary["Length"] != nil, dictionary.pdfInteger(named: "Length") == nil {
        throw PDFSecurityContext.malformed("The encryption key length must be an integer.")
      }
      let bits = dictionary.pdfInteger(named: "Length") ?? 40
      guard bits >= 40, bits <= 128, bits.isMultiple(of: 8) else {
        throw PDFSecurityContext.malformed("The legacy encryption key length is invalid.")
      }
      if version == 4, bits != 128 {
        throw PDFSecurityContext.malformed("V4 requires a 128-bit file key.")
      }
      return Int(bits / 8)
    }

    private static func cryptFilters(
      _ dictionary: [PDFName: PDFObject],
      version: Int,
      keyByteCount: Int,
      maximumCount: Int
    ) throws -> [PDFName: PDFCryptFilterDescription] {
      if version < 4 {
        return [
          PDFName("StdCF"): PDFCryptFilterDescription(
            name: PDFName("StdCF"), method: .rc4, keyByteCount: keyByteCount
          )
        ]
      }
      guard case .dictionary(let values) = dictionary["CF"] ?? .dictionary([:]),
        values.count <= maximumCount
      else { throw PDFSecurityContext.malformed("The crypt-filter dictionary is invalid.") }
      var filters = [PDFName: PDFCryptFilterDescription]()
      filters[PDFName("Identity")] = PDFCryptFilterDescription(
        name: PDFName("Identity"), method: .identity, keyByteCount: 0
      )
      for (name, object) in values {
        guard case .dictionary(let filter) = object,
          let methodName = filter.pdfName(named: "CFM")
        else { throw PDFSecurityContext.malformed("A crypt-filter entry is invalid.") }
        let method: PDFCryptFilterDescription.Method
        let length: Int
        switch methodName.bytes {
        case PDFName("V2").bytes:
          method = .rc4
          length = try cryptFilterLength(filter, default: keyByteCount, range: 5...16)
        case PDFName("AESV2").bytes:
          method = .aes128
          length = try cryptFilterLength(filter, default: 16, range: 16...16)
        case PDFName("AESV3").bytes:
          method = .aes256
          length = try cryptFilterLength(filter, default: 32, range: 32...32)
        default:
          throw PDFParsingError.unsupported(
            .cryptMethod(methodName),
            .init(offset: 0, message: "The crypt method is unsupported.")
          )
        }
        if version == 4, method == .aes256 {
          throw PDFSecurityContext.malformed("V4 cannot select AESV3.")
        }
        if version == 5, method != .aes256 {
          throw PDFSecurityContext.malformed("V5 crypt filters must select AESV3.")
        }
        if let event = filter.pdfName(named: "AuthEvent"),
          event != PDFName("DocOpen"), event != PDFName("EFOpen")
        {
          throw PDFSecurityContext.malformed("A crypt-filter AuthEvent is invalid.")
        }
        filters[name] = PDFCryptFilterDescription(name: name, method: method, keyByteCount: length)
      }
      return filters
    }

    private static func cryptFilterLength(
      _ dictionary: [PDFName: PDFObject],
      default defaultValue: Int,
      range: ClosedRange<Int>
    ) throws -> Int {
      let value = dictionary.pdfInteger(named: "Length").map(Int.init) ?? defaultValue
      guard range.contains(value) else {
        throw PDFSecurityContext.malformed("A crypt-filter key length is invalid.")
      }
      return value
    }

    private static func validate(
      filter name: PDFName,
      in filters: [PDFName: PDFCryptFilterDescription]
    ) throws {
      guard name == PDFName("Identity") || filters[name] != nil else {
        throw PDFSecurityContext.malformed("A default crypt filter names an undefined entry.")
      }
    }

    private static func requiredString(
      _ dictionary: [PDFName: PDFObject],
      name: PDFName,
      count: Int? = nil
    ) throws -> Data {
      guard case .string(let string) = dictionary[name], count == nil || string.bytes.count == count else {
        throw PDFSecurityContext.malformed("The encryption dictionary \(name) string is invalid.")
      }
      return string.bytes
    }

    private static func boolean(
      _ dictionary: [PDFName: PDFObject],
      name: PDFName,
      default defaultValue: Bool
    ) throws -> Bool {
      guard let object = dictionary[name] else { return defaultValue }
      guard case .boolean(let value) = object else {
        throw PDFSecurityContext.malformed("The encryption dictionary \(name) value is invalid.")
      }
      return value
    }
  }
}
