import Foundation

/// Contiguous scratch storage for the gray rasterizer's accumulated cells.
struct RasterCellArena: ~Copyable {
  private struct Cell {
    let column: Int
    var area: Int64
    var cover: Int64
    let next: Int
  }

  private static let pixelBits: Int64 = 8
  private static let onePixel: Int64 = 1 << pixelBits

  private let maximumCells: Int
  private var cells: ContiguousArray<Cell>
  private var rowHeads: ContiguousArray<Int>
  private var sortedIndices: ContiguousArray<Int>

  init(height: Int, maximumScratchBytes: Int) throws(RasterError) {
    guard height >= 0,
      height <= Int.max / MemoryLayout<Int>.stride
    else { throw .limitExceeded }
    let rowBytes = height * MemoryLayout<Int>.stride
    let bytesPerCell = MemoryLayout<Cell>.stride + MemoryLayout<Int>.stride
    guard rowBytes <= maximumScratchBytes,
      bytesPerCell > 0
    else { throw .limitExceeded }

    maximumCells = (maximumScratchBytes - rowBytes) / bytesPerCell
    cells = []
    rowHeads = ContiguousArray(repeating: -1, count: height)
    sortedIndices = []
  }

  mutating func record(
    column: Int,
    row: Int,
    area: Int64,
    cover: Int64
  ) throws(RasterError) {
    guard cells.count < maximumCells else { throw .limitExceeded }
    let next = rowHeads[row]
    cells.append(Cell(column: column, area: area, cover: cover, next: next))
    rowHeads[row] = cells.count - 1
  }

  mutating func sweep(rule: RasterFillRule, width: Int) -> [CoverageSpan] {
    var spans: [CoverageSpan] = []
    spans.reserveCapacity(cells.count)

    for row in rowHeads.indices where rowHeads[row] >= 0 {
      collectSortedIndices(for: row)
      var cover: Int64 = 0
      var x = 0
      var offset = 0
      while offset < sortedIndices.count {
        let column = cells[sortedIndices[offset]].column
        var area: Int64 = 0
        var coverDelta: Int64 = 0
        repeat {
          let cell = cells[sortedIndices[offset]]
          area += cell.area
          coverDelta += cell.cover
          offset += 1
        } while offset < sortedIndices.count
          && cells[sortedIndices[offset]].column == column

        if column > x, cover != 0 {
          appendSpan(
            x: x,
            y: row,
            length: column - x,
            area: cover * Self.onePixel * 2,
            rule: rule,
            to: &spans
          )
        }
        cover += coverDelta
        let accumulatedArea = cover * Self.onePixel * 2 - area
        if accumulatedArea != 0, column >= 0 {
          appendSpan(
            x: column,
            y: row,
            length: 1,
            area: accumulatedArea,
            rule: rule,
            to: &spans
          )
        }
        x = column + 1
      }
      if width > x, cover != 0 {
        appendSpan(
          x: x,
          y: row,
          length: width - x,
          area: cover * Self.onePixel * 2,
          rule: rule,
          to: &spans
        )
      }
    }
    return spans
  }

  private mutating func collectSortedIndices(for row: Int) {
    sortedIndices.removeAll(keepingCapacity: true)
    var index = rowHeads[row]
    while index >= 0 {
      sortedIndices.append(index)
      index = cells[index].next
    }
    sortedIndices.sort { cells[$0].column < cells[$1].column }
  }

  private func appendSpan(
    x: Int,
    y: Int,
    length: Int,
    area: Int64,
    rule: RasterFillRule,
    to spans: inout [CoverageSpan]
  ) {
    var coverage = Int(abs(area) >> (Self.pixelBits * 2 + 1 - 8))
    if rule == .evenOdd {
      coverage &= 511
      coverage = coverage > 256 ? 512 - coverage : coverage
      if coverage == 256 { coverage = 255 }
    } else if coverage >= 256 {
      coverage = 255
    }
    guard coverage > 0, length > 0, x >= 0 else { return }
    let value = UInt8(min(255, coverage))
    if let last = spans.last,
      last.y == y,
      last.x + last.length == x,
      last.coverage == value
    {
      spans[spans.count - 1].length += length
    } else {
      spans.append(CoverageSpan(x: x, y: y, length: length, coverage: value))
    }
  }
}
