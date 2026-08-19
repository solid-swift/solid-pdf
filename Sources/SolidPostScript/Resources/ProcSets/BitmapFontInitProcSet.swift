import Foundation

/// The standard Type 4 CIDFont bitmap-cache management procedures.
public struct BitmapFontInitProcSet: ProcSet {
  /// Creates the procedure-set provider.
  public init() {}
  /// The resource name.
  public var name: String { "BitmapFontInit" }

  /// Returns the procedure-set dictionary source.
  public func load() -> String {
    """
    true setglobal
    <<
      /addglyph /.addglyph load
      /removeglyphs /.removeglyphs load
      /removeall /.removeallglyphs load
    >>
    """
  }
}
