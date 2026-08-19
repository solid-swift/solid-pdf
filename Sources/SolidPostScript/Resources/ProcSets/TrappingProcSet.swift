import Foundation

/// The standard LanguageLevel 3 in-RIP trapping procedure set.
public struct TrappingProcSet: ProcSet {
  /// Creates the procedure-set provider.
  public init() {}

  /// The resource name.
  public var name: String { "Trapping" }

  /// Returns the procedure-set dictionary source.
  public func load() -> String {
    """
    true setglobal
    <<
      /settrapparams /.settrapparams load
      /currenttrapparams /.currenttrapparams load
      /settrapzone /.settrapzone load
    >>
    """
  }
}
