/// An error raised while validating or writing an incremental form update.
public enum PDFIncrementalUpdateError: Error, Sendable, Hashable {
  /// The document has no AcroForm.
  case missingAcroForm
  /// The transaction names the same field more than once.
  case duplicateField(PDFFormFieldIdentifier)
  /// A field identifier does not belong to the latest revision.
  case unknownField(PDFFormFieldIdentifier)
  /// The field cannot accept the requested update.
  case invalidFieldValue(PDFFormFieldIdentifier, reason: String)
  /// The document or field is read-only for the authenticated caller.
  case permissionDenied
  /// A signature transform prohibits the requested update.
  case signatureProhibitsUpdate(PDFFormFieldIdentifier?)
  /// XFA-backed form updates are intentionally unsupported.
  case unsupportedXFA
  /// A Unicode value has no exact representation in the field font.
  case unrepresentableText(PDFFormFieldIdentifier)
  /// An exact synchronized widget appearance could not be produced.
  case appearanceUnavailable(PDFAnnotationIdentifier)
  /// A configured update limit was exceeded.
  case limitExceeded
  /// The retained source changed after the document was opened.
  case sourceChanged
  /// The staged revision failed strict validation.
  case validationFailed
  /// The document was closed before the update completed.
  case documentClosed
  /// Output publication failed.
  case outputFailure
}
