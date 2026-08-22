import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFFormUpdateAuthorizationTests {
  @Test(arguments: [
    PDFCryptFilterDescription.Method.rc4,
    .aes128,
    .aes256,
  ])
  func encryptsRewrittenStringsAndStreams(
    _ method: PDFCryptFilterDescription.Method
  ) throws {
    let context = securityContext(method: method)
    let reference = try PDFObjectReference(objectNumber: 42, generationNumber: 3)
    let plaintext = Data("incremental secret".utf8)

    guard case .string(let encryptedString) = try context.encryptObject(
      .string(PDFString(bytes: plaintext, representation: .literal)),
      in: reference
    ) else {
      Issue.record("Expected an encrypted string")
      return
    }
    #expect(encryptedString.bytes != plaintext)
    #expect(try context.decryptString(encryptedString.bytes, in: reference) == plaintext)

    let encryptedStream = try context.encryptStream(plaintext, in: reference)
    #expect(encryptedStream != plaintext)
    let filter = try context.implicitStreamFilter(for: .ordinary, object: reference)
    var decrypted = try filter?.process(input: encryptedStream).output ?? Data()
    decrypted.append(try filter?.finish() ?? Data())
    #expect(decrypted == plaintext)
  }

  @Test
  func requiresFormFillingPermissionForUserCredentials() throws {
    let field = try textField(named: "Customer.Name")
    let update = PDFFormFieldUpdate(field: field.identifier, value: .text("Ada"))
    let transaction = PDFFormUpdateTransaction(updates: [update])
    let authorization = PDFFormUpdateAuthorization(
      security: securityContext(method: .rc4, permissions: []).security,
      signatures: [],
      fields: [field.identifier: field]
    )

    #expect(throws: PDFIncrementalUpdateError.permissionDenied) {
      try authorization.validate(transaction)
    }
  }

  @Test
  func ownerCredentialsBypassDocumentPermissionBits() throws {
    let field = try textField(named: "Customer.Name")
    let update = PDFFormFieldUpdate(field: field.identifier, value: .text("Ada"))
    let transaction = PDFFormUpdateTransaction(updates: [update])
    let security = PDFDocumentSecurity(
      encryption: securityContext(method: .rc4).security.encryption,
      authentication: .owner,
      rawPermissionFlags: 0,
      effectivePermissions: .all,
      streamFilter: PDFName("StdCF"),
      stringFilter: PDFName("StdCF"),
      embeddedFileFilter: PDFName("StdCF")
    )

    try PDFFormUpdateAuthorization(
      security: security,
      signatures: [],
      fields: [field.identifier: field]
    ).validate(transaction)
  }

  @Test
  func enforcesDocMDPAndFieldMDPBeforePlanning() throws {
    let field = try textField(named: "Customer.Name")
    let update = PDFFormFieldUpdate(field: field.identifier, value: .text("Ada"))
    let transaction = PDFFormUpdateTransaction(updates: [update])

    for transform in [
      PDFSignatureTransform.docMDP(.init(permissionLevel: 1, rawParameters: [:])),
      .fieldMDP(.init(
        action: .include,
        fieldNames: ["Customer.Name"],
        rawParameters: [:]
      )),
      .fieldMDP(.init(action: .all, fieldNames: [], rawParameters: [:])),
    ] {
      let authorization = PDFFormUpdateAuthorization(
        security: nil,
        signatures: [signature(transform: transform)],
        fields: [field.identifier: field]
      )
      #expect(throws: PDFIncrementalUpdateError.signatureProhibitsUpdate(field.identifier)) {
        try authorization.validate(transaction)
      }
    }
  }

  @Test
  func permitsDocMDPFormFillingAndExcludedField() throws {
    let field = try textField(named: "Customer.Name")
    let update = PDFFormFieldUpdate(field: field.identifier, value: .text("Ada"))
    let transaction = PDFFormUpdateTransaction(updates: [update])
    let signatures = [
      signature(transform: .docMDP(.init(permissionLevel: 2, rawParameters: [:]))),
      signature(transform: .fieldMDP(.init(
        action: .exclude,
        fieldNames: ["Customer.Name"],
        rawParameters: [:]
      ))),
    ]

    try PDFFormUpdateAuthorization(
      security: nil,
      signatures: signatures,
      fields: [field.identifier: field]
    ).validate(transaction)
  }

  private func securityContext(
    method: PDFCryptFilterDescription.Method,
    permissions: PDFPermissionSet = .all
  ) -> PDFSecurityContext {
    let keyByteCount = method == .aes256 ? 32 : 16
    let filter = PDFCryptFilterDescription(
      name: PDFName("StdCF"),
      method: method,
      keyByteCount: keyByteCount
    )
    let security = PDFDocumentSecurity(
      encryption: PDFEncryptionDescription(
        version: method == .aes256 ? 5 : 4,
        revision: method == .aes256 ? 6 : 4,
        keyBitCount: keyByteCount * 8,
        encryptsMetadata: true,
        cryptFilters: [filter]
      ),
      authentication: .user,
      rawPermissionFlags: permissions.rawValue,
      effectivePermissions: permissions,
      streamFilter: filter.name,
      stringFilter: filter.name,
      embeddedFileFilter: filter.name
    )
    return PDFSecurityContext(
      security: security,
      fileKey: Data((0..<keyByteCount).map(UInt8.init)),
      encryptionReference: nil,
      cryptFilters: [filter.name: filter]
    )
  }

  private func textField(named name: String) throws -> PDFFormField {
    let reference = try PDFObjectReference(objectNumber: 10, generationNumber: 0)
    return PDFFormField(
      identifier: PDFFormFieldIdentifier(reference: reference),
      parent: nil,
      children: [],
      widgets: [],
      type: .text,
      flags: [],
      partialName: name,
      fullyQualifiedName: name,
      alternateName: nil,
      mappingName: nil,
      value: nil,
      defaultValue: nil,
      options: [],
      maximumLength: nil,
      selectedOptionIndices: [],
      defaultAppearance: nil,
      justification: 0,
      resources: nil,
      actions: [:],
      richTextValue: nil,
      signature: nil,
      rawDictionary: [:],
      definingRevision: revision
    )
  }

  private func signature(transform: PDFSignatureTransform) -> PDFSignature {
    PDFSignature(
      byteRanges: [],
      contents: Data(),
      filter: nil,
      subfilter: nil,
      reason: nil,
      signingTime: nil,
      permissions: nil,
      rawDictionary: [:],
      definingRevision: revision,
      transforms: [transform]
    )
  }

  private var revision: PDFRevisionIdentifier {
    PDFRevisionIdentifier(
      documentIdentifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      ordinal: 0
    )
  }
}
