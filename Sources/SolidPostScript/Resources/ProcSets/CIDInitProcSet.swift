import Foundation

/// The standard CMap and CIDFont construction procedures.
public struct CIDInitProcSet: ProcSet {
  /// Creates the procedure-set provider.
  public init() {}
  /// The resource name.
  public var name: String { "CIDInit" }

  /// Returns the procedure-set dictionary source.
  public func load() -> String {
    """
    true setglobal
    <<
      /begincmap /.begincmap load /endcmap /.endcmap load
      /begincodespacerange /.begincodespacerange load
      /endcodespacerange /.endcodespacerange load
      /usefont /.usefont load /usecmap /.usecmap load
      /beginbfchar /.beginbfchar load /endbfchar /.endbfchar load
      /beginbfrange /.beginbfrange load /endbfrange /.endbfrange load
      /begincidchar /.begincidchar load /endcidchar /.endcidchar load
      /begincidrange /.begincidrange load /endcidrange /.endcidrange load
      /beginnotdefchar /.beginnotdefchar load /endnotdefchar /.endnotdefchar load
      /beginnotdefrange /.beginnotdefrange load /endnotdefrange /.endnotdefrange load
      /beginusematrix /.beginusematrix load /endusematrix /.endusematrix load
      /StartData /.cidstartdata load
      /beginrearrangedfont { pop mark } bind
      /endrearrangedfont { counttomark array astore exch pop /FDepVector exch def } bind
    >>
    """
  }
}
