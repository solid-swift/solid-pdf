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
}
