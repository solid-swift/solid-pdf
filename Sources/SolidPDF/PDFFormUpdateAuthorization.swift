struct PDFFormUpdateAuthorization {
  let security: PDFDocumentSecurity?
  let signatures: [PDFSignature]
  let fields: [PDFFormFieldIdentifier: PDFFormField]

  func validate(_ transaction: PDFFormUpdateTransaction) throws {
    if let security,
      security.authentication != .owner,
      !security.effectivePermissions.contains(.fillForms),
      !security.effectivePermissions.contains(.modify),
      !security.effectivePermissions.contains(.annotate)
    {
      throw PDFIncrementalUpdateError.permissionDenied
    }
    for update in transaction.updates {
      guard let field = fields[update.field] else {
        throw PDFIncrementalUpdateError.unknownField(update.field)
      }
      for signature in signatures {
        for transform in signature.transforms {
          switch transform {
          case .docMDP(let transform) where transform.permissionLevel == 1:
            throw PDFIncrementalUpdateError.signatureProhibitsUpdate(update.field)
          case .docMDP:
            break
          case .fieldMDP(let transform):
            let name = field.fullyQualifiedName
            let listed = name.map(transform.fieldNames.contains) ?? false
            let locked = switch transform.action {
            case .all: true
            case .include: listed
            case .exclude: !listed
            }
            if locked { throw PDFIncrementalUpdateError.signatureProhibitsUpdate(update.field) }
          case .unsupported:
            throw PDFIncrementalUpdateError.signatureProhibitsUpdate(update.field)
          }
        }
      }
    }
  }

  func modificationStatuses(
    changed: [PDFObjectReference]
  ) -> [PDFSignatureIdentifier: PDFSignatureModificationStatus] {
    Dictionary(uniqueKeysWithValues: signatures.compactMap { signature in
      signature.identifier.map { ($0, .permitted(changedObjects: changed)) }
    })
  }
}
