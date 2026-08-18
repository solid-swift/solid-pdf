@testable import SolidRaster
import Testing

@Suite struct RasterCellArenaTests {
  @Test func sweepsRowsAndColumnsInDisplayOrder() throws {
    var arena = try RasterCellArena(height: 3, maximumScratchBytes: 4_096)
    try arena.record(column: 2, row: 2, area: -131_072, cover: 0)
    try arena.record(column: 1, row: 0, area: -131_072, cover: 0)
    try arena.record(column: 3, row: 0, area: -131_072, cover: 0)

    let spans = arena.sweep(rule: .winding, width: 8)

    #expect(spans.map(\.x) == [1, 3, 2])
    #expect(spans.map(\.y) == [0, 0, 2])
  }

  @Test func mergesDuplicateCellsBeforeComputingCoverage() throws {
    var arena = try RasterCellArena(height: 1, maximumScratchBytes: 4_096)
    try arena.record(column: 2, row: 0, area: -65_536, cover: 0)
    try arena.record(column: 2, row: 0, area: -65_536, cover: 0)

    let spans = arena.sweep(rule: .winding, width: 8)

    #expect(spans == [CoverageSpan(x: 2, y: 0, length: 1, coverage: 255)])
  }

  @Test func rejectsGrowthBeforeMutatingStorage() throws {
    let rowBytes = MemoryLayout<Int>.stride
    let oneCellBudget = rowBytes + 64
    var arena = try RasterCellArena(height: 1, maximumScratchBytes: oneCellBudget)
    try arena.record(column: 1, row: 0, area: -131_072, cover: 0)

    #expect(throws: RasterError.limitExceeded) {
      try arena.record(column: 2, row: 0, area: -131_072, cover: 0)
    }
    #expect(arena.sweep(rule: .winding, width: 8).count == 1)
  }
}
