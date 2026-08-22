/// A resolved indirect PDF object and its source provenance.
public struct PDFIndirectObject: Sendable, Hashable {
  /// The reference used to identify the object.
  public let reference: PDFObjectReference
  /// The resolved direct value or stream.
  public let value: PDFResolvedObject
  /// The direct file range, absent for an object-stream member.
  public let sourceRange: PDFSourceRange?
  /// The object's direct-file or object-stream provenance.
  public let provenance: PDFObjectProvenance

  /// Creates a resolved indirect object.
  public init(
    reference: PDFObjectReference,
    value: PDFResolvedObject,
    sourceRange: PDFSourceRange?,
    provenance: PDFObjectProvenance
  ) {
    self.reference = reference
    self.value = value
    self.sourceRange = sourceRange
    self.provenance = provenance
  }
}

extension PDFIndirectObject: CustomStringConvertible {
  /// A stable concise description of the object identity and provenance.
  public var description: String {
    let storage = switch provenance {
    case .file: "file"
    case .objectStream(let container, let index):
      "object stream \(container.objectNumber)[\(index)]"
    }
    return "\(reference.objectNumber) \(reference.generationNumber) obj (\(storage))"
  }
}
