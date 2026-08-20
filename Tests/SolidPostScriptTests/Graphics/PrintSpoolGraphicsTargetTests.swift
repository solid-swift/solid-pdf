import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct PrintSpoolGraphicsTargetTests {
  @Test func uncollatedCopiesReferenceEachLogicalPageOnce() async throws {
    let result = try await Interpreter.render(
      content: """
        << /NumCopies 2 >> setpagedevice
        0 0 moveto 10 0 lineto stroke showpage
        0 0 moveto 20 0 lineto stroke showpage
      """,
      to: PrintSpoolGraphicsTarget()
    )

    #expect(result.output.pages.count == 2)
    #expect(result.output.pageSets.count == 2)
    #expect(result.output.sheets.count == 4)
    #expect(result.output.sheets.compactMap(\.front?.pageIndex) == [0, 0, 1, 1])
    #expect(result.output.pages.map(\.effects.count) == [2, 1])
  }

  @Test func duplexPairsConsecutiveSidesAndLeavesFinalVersoBlank() async throws {
    let result = try await Interpreter.render(
      content: """
        << /Duplex true >> setpagedevice
        showpage showpage showpage
      """,
      to: PrintSpoolGraphicsTarget()
    )

    #expect(result.output.sheets.count == 2)
    #expect(result.output.sheets[0].front?.pageIndex == 0)
    #expect(result.output.sheets[0].back?.pageIndex == 1)
    #expect(result.output.sheets[1].front?.pageIndex == 2)
    #expect(result.output.sheets[1].back == nil)
    #expect(result.output.sheets[0].front?.placement.side == .recto)
    #expect(result.output.sheets[0].back?.placement.side == .verso)
  }

  @Test func collatedCopiesCreateFreshDuplexSets() async throws {
    let result = try await Interpreter.render(
      content: """
        << /Duplex true /Collate true /NumCopies 2 >> setpagedevice
        showpage showpage showpage
      """,
      to: PrintSpoolGraphicsTarget()
    )

    #expect(result.output.pages.count == 3)
    #expect(result.output.pageSets.count == 2)
    #expect(result.output.pageSets.allSatisfy { $0.isCollated })
    #expect(result.output.pageSets.map(\.pageIndices) == [[0, 1, 2], [0, 1, 2]])
    #expect(result.output.sheets.count == 4)
    #expect(result.output.sheets[1].back == nil)
    #expect(result.output.sheets[2].front?.pageIndex == 0)
  }

  @Test func outputDestinationFaceOrderAndActionsArePreserved() async throws {
    let destinationType = Data("Upper".utf8)
    let target = PrintSpoolGraphicsTarget(outputDestinations: GraphicsOutputCatalog(
      destinations: [
        1: GraphicsOutputDestination(position: 1, type: Data("Lower".utf8)),
        2: GraphicsOutputDestination(position: 2, type: destinationType),
      ],
      priority: [2, 1]
    ))
    let result = try await Interpreter.render(
      content: """
        << /OutputType (Upper) /OutputFaceUp true
           /RollFedMedia true /AdvanceMedia 4 /AdvanceDistance 9 /CutMedia 3 /Jog 3
        >> setpagedevice
        showpage showpage
      """,
      to: target
    )

    #expect(result.output.sheets.allSatisfy { $0.destination?.position == 2 })
    #expect(result.output.physicalDeliveryOrder == [0, 1])
    #expect(result.output.stackReadOrder == [1, 0])
    #expect(result.output.actions.contains {
      $0.kind == .advance(distance: 9) && $0.boundary == .pageTransmission
    })
    #expect(result.output.actions.contains { $0.kind == .cut && $0.boundary == .pageSet })
    #expect(result.output.actions.contains { $0.kind == .jog && $0.boundary == .pageSet })
  }

  @Test func insertedSheetDiscardsCapturedMarks() async throws {
    let size = GraphicsSize(width: 612, height: 792)
    let target = PrintSpoolGraphicsTarget(inputMedia: GraphicsMediaCatalog(sources: [
      3: GraphicsMediaSource(
        position: 3,
        attributes: GraphicsMediaAttributes(pageSize: size, insertsSheet: true)
      ),
    ]))
    let result = try await Interpreter.render(
      content: """
        << /InsertSheet true >> setpagedevice
        0 0 moveto 100 100 lineto stroke showpage
      """,
      to: target
    )

    #expect(result.output.pages.count == 1)
    #expect(result.output.pages[0].isInsertedSheet)
    #expect(result.output.pages[0].effects.isEmpty)
    #expect(result.output.sheets[0].front?.isInsertedSheet == true)
    #expect(result.output.sheets[0].back == nil)
  }

  @Test func deliveredSideLimitRaisesCatchableLimitCheck() async throws {
    let result = try await Interpreter.render(
      content: """
        << /NumCopies 2 >> setpagedevice
        { showpage } stopped
        $error /errorname get
      """,
      to: PrintSpoolGraphicsTarget(limits: GraphicsPrintSpoolLimits(maximumDeliveredSides: 1))
    )
    let values = try await result.context.results()

    #expect(try values[1].value(as: BooleanValue.self).value)
    #expect(try values[0].value(as: NameValue.self).value == "limitcheck")
  }

  @Test func compatiblePageDeviceChangesRemainInOneCollatedSection() async throws {
    let result = try await Interpreter.render(
      content: """
        << /Collate true /NumCopies 2 >> setpagedevice
        showpage
        << /PageOffset [12 0] >> setpagedevice
        showpage
      """,
      to: PrintSpoolGraphicsTarget()
    )

    #expect(result.output.pageSets.count == 2)
    #expect(result.output.pageSets.map(\.pageIndices) == [[0, 1], [0, 1]])
  }

  @Test func physicalSeparationsBecomeDistinctDeliveredSides() async throws {
    let result = try await Interpreter.render(
      content: """
        << /ProcessColorModel /DeviceCMYK /Separations true
           /SeparationOrder [/Cyan /Magenta /Yellow /Black]
        >> setpagedevice
        showpage
      """,
      to: PrintSpoolGraphicsTarget()
    )

    #expect(result.output.sheets.count == 4)
    #expect(result.output.sheets.compactMap(\.front?.separationColorant) == [
      "Cyan", "Magenta", "Yellow", "Black",
    ])
  }
}
