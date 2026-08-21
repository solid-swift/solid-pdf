/// A one-based selection of transmitted pages.
public enum PostScriptDocumentPageSelection: Sendable, Hashable {
  case all
  case pages(Set<Int>)

  /// Returns whether a transmitted page ordinal is selected.
  public func contains(_ ordinal: Int) -> Bool {
    switch self { case .all: true; case .pages(let pages): pages.contains(ordinal) }
  }
}
