/// The numbering style used by a PDF page-label range.
public enum PDFPageLabelStyle: Sendable, Hashable {
  /// Decimal Arabic numerals.
  case decimal
  /// Uppercase Roman numerals.
  case uppercaseRoman
  /// Lowercase Roman numerals.
  case lowercaseRoman
  /// Repeated uppercase Latin letters.
  case uppercaseLetters
  /// Repeated lowercase Latin letters.
  case lowercaseLetters
  /// A prefix without an automatically generated number.
  case none
}

/// One explicit range in a catalog's page-label number tree.
public struct PDFPageLabelRange: Sendable, Hashable {
  /// The zero-based first page governed by this range.
  public let startPageIndex: Int
  /// The optional text prefix.
  public let prefix: String
  /// The numbering style, or `.none` for prefix-only labels.
  public let style: PDFPageLabelStyle
  /// The first numeric value used by the range.
  public let startNumber: Int

  /// Creates a page-label range.
  public init(
    startPageIndex: Int,
    prefix: String,
    style: PDFPageLabelStyle,
    startNumber: Int
  ) {
    self.startPageIndex = startPageIndex
    self.prefix = prefix
    self.style = style
    self.startNumber = startNumber
  }
}

/// The explicit page label effective for one page.
public struct PDFPageLabel: Sendable, Hashable {
  /// The zero-based labeled page index.
  public let pageIndex: Int
  /// The rendered label text.
  public let text: String
  /// The range that produced this label.
  public let range: PDFPageLabelRange

  /// Creates an effective page label.
  public init(pageIndex: Int, text: String, range: PDFPageLabelRange) {
    self.pageIndex = pageIndex
    self.text = text
    self.range = range
  }
}
