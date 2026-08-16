//
//  DataFileTests.swift
//

import Foundation
import SolidPostScript
import Testing

@Suite
struct DataFileTests {

  @Test
  func resetDoesNotRewindAnUnbufferedFile() throws {
    let file = DataFile(data: Data([1, 2, 3]), mode: .read)

    #expect(try file.readByte() == 1)
    try file.reset()
    #expect(try file.readByte() == 2)

    try file.close()
    try file.reset()
  }

  @Test
  func flushDiscardsRemainingInput() throws {
    let file = DataFile(data: Data([1, 2, 3]), mode: .read)

    #expect(try file.readByte() == 1)
    try file.flush()
    #expect(try file.readByte() == nil)
    #expect(try file.available == 0)
  }

  @Test
  func invalidReadAndPositionProduceRangeCheck() throws {
    let file = DataFile(data: Data([1, 2, 3]), mode: .read)

    #expect(throws: Error.rangeCheck) {
      try file.read(max: -1)
    }
    #expect(throws: Error.rangeCheck) {
      try file.setOffset(-1)
    }
  }

  @Test
  func writesReplaceOnlyTheirRangeAndAdvanceThePosition() throws {
    let file = DataFile(data: Data("abcdef".utf8), mode: .readWrite)

    try file.setOffset(2)
    try file.write(contentsOf: Data("XY".utf8))
    #expect(try file.offset == 4)

    try file.setOffset(4)
    try file.write(contentsOf: Data("1234".utf8))
    #expect(try file.offset == 8)

    try file.write(contentsOf: Data("!".utf8))
    #expect(try file.offset == 9)

    try file.write(contentsOf: Data())
    #expect(try file.offset == 9)

    try file.setOffset(0)
    #expect(try file.read(max: 9) == Data("abXY1234!".utf8))
  }

  @Test
  func closeIsIdempotent() throws {
    let file = DataFile(data: Data(), mode: .read)

    try file.close()
    try file.close()

    #expect(file.isClosed)
  }
}
