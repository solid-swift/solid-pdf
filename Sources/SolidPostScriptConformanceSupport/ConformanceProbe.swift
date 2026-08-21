import Foundation

package enum ConformanceProbe {
  package static let header = "SPS-CONFORMANCE 1"

  package static func instrument(_ source: Data, mode: ConformanceCaseMode) throws -> Data {
    guard mode == .wrapped else { return source }
    var result = Data((prologue + "\nCT begin\n").utf8)
    result.append(source)
    result.append(Data("\nend\n".utf8))
    return result
  }

  // This intentionally uses only Level 1 operators so the observation protocol does
  // not accidentally depend on the feature under test.
  private static let prologue = #"""
    /CT 32 dict def
    CT begin
    /ctout (%stdout) (w) file def
    /ctwrite { ctout exch writestring } bind def
    /cthex { ctout exch writehexstring } bind def
    /emit {
      /ctvalue exch def /ctlabel exch def
      (V ) ctwrite ctlabel cthex ( ) ctwrite
      ctvalue type
      dup /nulltype eq { pop (null -) ctwrite }
      { dup /booleantype eq { pop (boolean ) ctwrite ctvalue 8 string cvs ctwrite }
        { dup /integertype eq { pop (integer ) ctwrite ctvalue 32 string cvs ctwrite }
          { dup /realtype eq { pop (real ) ctwrite ctvalue 64 string cvs ctwrite }
            { dup /nametype eq { pop (name ) ctwrite ctvalue 4096 string cvs cthex }
              { dup /stringtype eq { pop (string ) ctwrite ctvalue cthex }
                { dup /arraytype eq exch /packedarraytype eq or
                  { (array ) ctwrite ctvalue length 32 string cvs ctwrite }
                  { typecheck }
                  ifelse
                } ifelse
              } ifelse
            } ifelse
          } ifelse
        } ifelse
      } ifelse
      (\n) ctwrite ctout flushfile
    } bind def
    (SPS-CONFORMANCE 1\n) ctwrite ctout flushfile
    end
    """#
}
