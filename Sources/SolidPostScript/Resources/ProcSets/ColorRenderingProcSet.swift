import Foundation

/// The standard customization procedures used by `findcolorrendering`.
struct ColorRenderingProcSet: ProcSet {
  let name = "ColorRendering"

  func load() -> String {
    """
    true setglobal
    <<
      /GetPageDeviceName {
        currentpagedevice dup /PageDeviceName known
          { /PageDeviceName get dup null eq { pop /none } if }
          { pop /none }
        ifelse
      }
      /GetHalftoneName {
        currenthalftone dup /HalftoneName known
          { /HalftoneName get }
          { pop /none }
        ifelse
      }
      /GetSubstituteCRD { pop /DefaultColorRendering }
    >>
    """
  }
}
