import Testing

@testable import SolidPostScript

@Suite struct PatternTests {
  @Test func makePatternIsLocalReadOnlyAndDefersPaintProc() async throws {
    let result = try await Interpreter.render(
      content: """
      /painted false def
      true setglobal
      << /PatternType 1 /PaintType 1 /TilingType 1
         /BBox [0 0 10 10] /XStep 10 /YStep 10
         /PaintProc { pop /painted true store 0 setgray 0 0 5 5 rectfill }
      >> matrix makepattern
      false setglobal
      dup gcheck exch rcheck painted
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(try values[0].value(as: BooleanValue.self).value == false)
    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[2].value(as: BooleanValue.self).value == false)
  }

  @Test func coloredPatternCompilesADeviceSpaceDisplayList() async throws {
    let result = try await Interpreter.render(
      content: """
      /p << /PatternType 1 /PaintType 1 /TilingType 1
        /BBox [0 0 10 10] /XStep 10 /YStep 10
        /PaintProc { pop 0 setgray 0 0 5 5 rectfill }
      >> matrix makepattern def
      /Pattern setcolorspace p setcolor
      0 0 20 20 rectfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .fillRectangles(_, let state) = try #require(page.effects.first),
      case .pattern(.tiling(let pattern, underlying: nil)) = state.paint
    else {
      Issue.record("Expected a colored tiling pattern")
      return
    }
    #expect(pattern.paintType == 1)
    #expect(pattern.displayList.effects.count == 1)
  }

  @Test func uncoloredPatternUsesTheUnderlyingColorAndRejectsCellColorChanges() async throws {
    let context = try await Interpreter.execute(content: """
      /p << /PatternType 1 /PaintType 2 /TilingType 2
        /BBox [0 0 4 4] /XStep 4 /YStep 4
        /PaintProc { pop 0 0 4 4 rectfill }
      >> matrix makepattern def
      0.25 setgray p setpattern currentcolor
      """)
    let values = try await context.results()
    #expect(try values[0].value(as: DictionaryValue.self).access == .readOnly)
    #expect(try values[1].value(as: RealValue.self).value == 0.25)

    let error: NameValue = try await Interpreter.result(content: """
      /p << /PatternType 1 /PaintType 2 /TilingType 1
        /BBox [0 0 4 4] /XStep 4 /YStep 4
        /PaintProc { pop 1 setgray 0 0 4 4 rectfill }
      >> matrix makepattern def
      0 setgray { p setpattern } stopped $error /errorname get
      """)
    #expect(error.value == "undefined")
  }

  @Test func patternRecursionAndPageTransmissionAreRejected() async throws {
    let pageError: NameValue = try await Interpreter.result(content: """
      /p << /PatternType 1 /PaintType 1 /TilingType 1
        /BBox [0 0 1 1] /XStep 1 /YStep 1 /PaintProc { pop showpage }
      >> matrix makepattern def
      /Pattern setcolorspace { p setcolor } stopped $error /errorname get
      """)
    #expect(pageError.value == "undefined")
  }
}
