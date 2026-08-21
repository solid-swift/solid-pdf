import Foundation

/// The standard Compact Font Format font-set construction procedures.
public struct FontSetInitProcSet: ProcSet {
  /// Creates the procedure-set provider.
  public init() {}

  /// The resource name.
  public var name: String { "FontSetInit" }

  /// Returns the procedure-set dictionary source.
  public func load() -> String {
    """
    true setglobal
    << /StartData /.fontsetstartdata load >>
    """
  }
}
