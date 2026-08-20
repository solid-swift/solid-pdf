/// The language-level kind identified for a PostScript document.
public enum PostScriptDocumentKind: Sendable, Hashable {
  /// An ordinary PostScript program.
  case postScript
  /// An Encapsulated PostScript illustration.
  case encapsulatedPostScript
}
