import SolidPDF
import SolidPostScript

/// Ordering used for extracted text spans.
public enum PDFTextExtractionOrder: Sendable, Hashable {
  /// Preserve content-stream painting order.
  case physical
  /// Use the logical structure tree when present, followed by unassociated physical content.
  case structure
}

/// The document semantic source of one extracted text span.
public enum PDFExtractedTextSource: Sendable, Hashable {
  /// Text painted by the page's content streams.
  case pageContent
  /// Text painted by an annotation or widget appearance.
  case appearance(annotation: PDFAnnotationIdentifier, field: PDFFormFieldIdentifier?)
  /// Text stored directly in an annotation dictionary.
  case annotationText(PDFAnnotationIdentifier)
  /// An authoritative AcroForm value without invented glyph geometry.
  case formValue(field: PDFFormFieldIdentifier, widget: PDFAnnotationIdentifier)
}

/// Options for semantic PDF text extraction.
public struct PDFTextExtractionOptions: Sendable {
  public var order: PDFTextExtractionOrder
  public var includeHiddenContent: Bool
  public var includeArtifacts: Bool
  public var includeAnnotations: Bool
  public var includeAnnotationAppearances: Bool
  public var accessPurpose: PDFGraphicsAccessPurpose
  public var strict: Bool
  public var optionalContentSelection: PDFOptionalContentSelection
  public var optionalContentContext: PDFOptionalContentContext
  public var fontEnvironment: PDFGraphicsFontEnvironment
  public var limits: PDFGraphicsLimits

  public init(
    order: PDFTextExtractionOrder = .structure,
    includeHiddenContent: Bool = false,
    includeArtifacts: Bool = false,
    includeAnnotations: Bool = true,
    includeAnnotationAppearances: Bool = true,
    accessPurpose: PDFGraphicsAccessPurpose = .extraction,
    strict: Bool = true,
    optionalContentSelection: PDFOptionalContentSelection = .documentDefault,
    optionalContentContext: PDFOptionalContentContext = .init(),
    fontEnvironment: PDFGraphicsFontEnvironment = .portable,
    limits: PDFGraphicsLimits = .init()
  ) {
    self.order = order
    self.includeHiddenContent = includeHiddenContent
    self.includeArtifacts = includeArtifacts
    self.includeAnnotations = includeAnnotations
    self.includeAnnotationAppearances = includeAnnotationAppearances
    self.accessPurpose = accessPurpose
    self.strict = strict
    self.optionalContentSelection = optionalContentSelection
    self.optionalContentContext = optionalContentContext
    self.fontEnvironment = fontEnvironment
    self.limits = limits
  }
}

/// One semantically coherent extracted text span.
public struct PDFExtractedTextSpan: Sendable, Hashable {
  /// The page, appearance, annotation, or field value that supplied this text.
  public let source: PDFExtractedTextSource
  /// Logical text when an authoritative mapping or replacement is available.
  public let text: String?
  /// The glyph runs contributing physical styling and geometry.
  public let runs: [GraphicsGlyphRun]
  /// Active marked-content scopes in outer-to-inner order.
  public let markedContentPath: [GraphicsMarkedContentScope]
  /// Structure elements in root-to-leaf order.
  public let structurePath: [PDFStructureElementIdentifier]
  /// Evaluated optional-content visibility.
  public let visibility: GraphicsContentVisibility
  /// Bounds in target device space.
  public let deviceBounds: GraphicsRect?
  /// Bounds in default-user-space page points when the mapping is invertible.
  public let pageBounds: GraphicsRect?
  /// The originating annotation, when applicable.
  public let annotationIdentifier: PDFAnnotationIdentifier?
  /// The originating widget annotation, when applicable.
  public let widgetIdentifier: PDFAnnotationIdentifier?
  /// The originating AcroForm field, when applicable.
  public let formFieldIdentifier: PDFFormFieldIdentifier?
}

/// Extracted text and diagnostics for one transmitted PDF page.
public struct PDFExtractedTextPage: Sendable, Hashable {
  public let revision: PDFRevisionIdentifier
  public let pageIndex: Int
  public let pageReference: PDFObjectReference
  public let spans: [PDFExtractedTextSpan]
  public let diagnostics: [PDFGraphicsDiagnostic]
}

/// A single-pass, explicitly closable sequence of extracted PDF pages.
public final class PDFExtractedTextSequence: AsyncSequence, AsyncIteratorProtocol, Sendable {
  public typealias Element = PDFExtractedTextPage
  public typealias AsyncIterator = PDFExtractedTextSequence

  private let state: PDFExtractedTextSequenceState

  package init(state: PDFExtractedTextSequenceState) { self.state = state }

  deinit {
    let state = state
    Task { await state.close() }
  }

  public func makeAsyncIterator() -> PDFExtractedTextSequence { self }

  /// Extracts the next selected page.
  public func next() async throws -> PDFExtractedTextPage? { try await state.next() }

  /// Abandons extraction and releases sequence state.
  public func close() async { await state.close() }
}

package actor PDFExtractedTextSequenceState {
  typealias Extract = @Sendable (Int) async throws -> PDFExtractedTextPage

  private let indices: [Int]
  private let extract: Extract
  private var offset = 0
  private var closed = false

  init(indices: [Int], extract: @escaping Extract) {
    self.indices = indices
    self.extract = extract
  }

  func next() async throws -> PDFExtractedTextPage? {
    guard !closed, offset < indices.count else { closed = true; return nil }
    do {
      let page = try await extract(indices[offset])
      offset += 1
      return page
    } catch {
      closed = true
      throw error
    }
  }

  func close() { closed = true }
}
