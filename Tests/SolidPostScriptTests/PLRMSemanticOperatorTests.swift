import Testing

@testable import SolidPostScript

@Suite
struct PLRMSemanticOperatorTests {
  @Test(arguments: semanticOperatorVectors)
  fileprivate func auditedOperatorProducesItsPLRMResult(_ vector: SemanticOperatorVector) async throws {
    let result: BooleanValue = try await Interpreter.result(content: vector.program)
    #expect(result.value, "Semantic vector failed for /\(vector.name)")
  }
}

private struct SemanticOperatorVector: Sendable, CustomTestStringConvertible {
  let name: String
  let program: String

  var testDescription: String { name }
}

private let semanticOperatorVectors = [
  SemanticOperatorVector(
    name: "arcn",
    program:
      "newpath 0 0 10 0 90 arcn currentpoint /y exch def /x exch def x abs .0001 lt y 10 sub abs .0001 lt and"
  ),
  fontVector("ashow", body: "0 0 moveto 5 7 (A) ashow currentpoint /y exch def /x exch def x 65 eq y 7 eq and"),
  fontVector(
    "awidthshow",
    body: "0 0 moveto 2 3 65 5 7 (A) awidthshow currentpoint /y exch def /x exch def x 67 eq y 10 eq and"
  ),
  SemanticOperatorVector(
    name: "concatmatrix",
    program:
      "[2 0 0 3 4 5] [1 0 0 1 0 0] matrix concatmatrix /m exch def m 0 get 2 eq m 3 get 3 eq and m 5 get 5 eq and"
  ),
  SemanticOperatorVector(
    name: "currentblackgeneration",
    program: "currentblackgeneration .25 exch exec 0 eq"
  ),
  SemanticOperatorVector(
    name: "currentcolorscreen",
    program: "currentcolorscreen count 12 eq"
  ),
  SemanticOperatorVector(
    name: "currentcolortransfer",
    program: "currentcolortransfer /gray exch def /blue exch def /green exch def /red exch def 0 red exec 0 eq"
  ),
  SemanticOperatorVector(
    name: "currenthsbcolor",
    program:
      ".5 .25 .75 sethsbcolor currenthsbcolor /b exch def /s exch def /h exch def h .5 sub abs .0001 lt s .25 sub abs .0001 lt and b .75 sub abs .0001 lt and"
  ),
  SemanticOperatorVector(
    name: "currentundercolorremoval",
    program: "currentundercolorremoval .25 exch exec 0 eq"
  ),
  SemanticOperatorVector(
    name: "defaultmatrix",
    program:
      "initmatrix matrix currentmatrix /current exch def matrix defaultmatrix /default exch def true 0 1 5 { /i exch def current i get default i get eq and } for"
  ),
  SemanticOperatorVector(
    name: "eoclip",
    program:
      "newpath 0 0 moveto 10 0 lineto 10 10 lineto closepath eoclip pathbbox /ury exch def /urx exch def /lly exch def /llx exch def llx 0 eq lly 0 eq and urx 10 eq and ury 10 eq and"
  ),
  SemanticOperatorVector(
    name: "erasepage",
    program:
      ".25 setgray 3 4 moveto erasepage currentpoint /y exch def /x exch def x 3 eq y 4 eq and currentgray .25 eq and"
  ),
  SemanticOperatorVector(
    name: "findencoding",
    program: "/StandardEncoding findencoding StandardEncoding eq"
  ),
  fontVector(
    "glyphshow",
    body: "0 0 moveto /A glyphshow currentpoint /y exch def /x exch def x 60 eq y 0 eq and"
  ),
  SemanticOperatorVector(
    name: "grestoreall",
    program: "2 setlinewidth grestoreall currentlinewidth 2 eq"
  ),
  SemanticOperatorVector(
    name: "identmatrix",
    program: "matrix identmatrix /m exch def m 0 get 1 eq m 3 get 1 eq and m 4 get 0 eq and m 5 get 0 eq and"
  ),
  SemanticOperatorVector(
    name: "inueofill",
    program: "5 5 {0 0 10 10 setbbox 0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath} inueofill"
  ),
  SemanticOperatorVector(
    name: "invertmatrix",
    program: "[2 0 0 4 0 0] matrix invertmatrix /m exch def m 0 get .5 eq m 3 get .25 eq and"
  ),
  SemanticOperatorVector(
    name: "rcurveto",
    program:
      "10 20 moveto 1 2 3 4 5 6 rcurveto currentpoint /y exch def /x exch def x 15 eq y 26 eq and"
  ),
  SemanticOperatorVector(
    name: "rectstroke",
    program: "1 2 moveto 0 0 10 10 rectstroke currentpoint /y exch def /x exch def x 1 eq y 2 eq and"
  ),
  fontVector("rootfont", body: "currentfont rootfont eq"),
  SemanticOperatorVector(
    name: "rotate",
    program:
      "initmatrix 90 rotate 1 0 dtransform /y exch def /x exch def x abs .0001 lt y 1 sub abs .0001 lt and"
  ),
  fontVector("selectfont", selectWithOperator: true, body: "currentfont /FontName get /F eq"),
  fontVector(
    "setcachedevice2",
    buildGlyph: "pop pop 600 0 0 0 600 700 0 -900 250 880 setcachedevice2",
    body: "0 0 moveto (A) show currentpoint pop 60 eq"
  ),
  SemanticOperatorVector(
    name: "setcacheparams",
    program:
      "mark 111 222 setcacheparams currentuserparams /MaxFontItem get 222 eq currentuserparams /MinFontCompress get 111 eq and"
  ),
  SemanticOperatorVector(
    name: "setcolortransfer",
    program:
      "{pop .1} {pop .2} {pop .3} {pop .4} setcolortransfer currentcolortransfer /gray exch def /blue exch def /green exch def /red exch def 0 red exec .1 eq 0 green exec .2 eq and 0 blue exec .3 eq and 0 gray exec .4 eq and"
  ),
  SemanticOperatorVector(
    name: "sethsbcolor",
    program:
      "0 0 .5 sethsbcolor currentrgbcolor /b exch def /g exch def /r exch def r .5 eq g .5 eq and b .5 eq and"
  ),
  SemanticOperatorVector(
    name: "setmatrix",
    program: "[2 0 0 3 4 5] setmatrix matrix currentmatrix /m exch def m 0 get 2 eq m 3 get 3 eq and m 5 get 5 eq and"
  ),
  SemanticOperatorVector(
    name: "setvmthreshold",
    program: "123 setvmthreshold currentuserparams /VMThreshold get 123 eq"
  ),
  SemanticOperatorVector(
    name: "ueofill",
    program: "{0 0 10 10 setbbox 0 0 moveto 10 0 lineto 10 10 lineto 0 10 lineto closepath} ueofill count 0 eq"
  ),
  fontVector(
    "widthshow",
    body: "0 0 moveto 2 3 65 (A) widthshow currentpoint /y exch def /x exch def x 62 eq y 3 eq and"
  ),
  fontVector("xshow", body: "0 0 moveto (A) [10] xshow currentpoint pop 10 eq"),
  fontVector(
    "xyshow",
    body: "0 0 moveto (A) [30 40] xyshow currentpoint /y exch def /x exch def x 30 eq y 40 eq and"
  ),
  fontVector("yshow", body: "0 0 moveto (A) [20] yshow currentpoint exch pop 20 eq"),
]

private func fontVector(
  _ name: String,
  selectWithOperator: Bool = false,
  buildGlyph: String = "pop pop 600 0 0 0 600 700 setcachedevice",
  body: String
) -> SemanticOperatorVector {
  SemanticOperatorVector(
    name: name,
    program:
      """
      /F 12 dict dup begin
        /FontType 3 def
        /FontMatrix [.001 0 0 .001 0 0] def
        /FontBBox [0 0 600 700] def
        /Encoding StandardEncoding def
        /BuildGlyph { \(buildGlyph) } bind def
      end definefont pop
      \(selectWithOperator ? "/F 100 selectfont" : "/F findfont 100 scalefont setfont")
      \(body)
      """
  )
}
