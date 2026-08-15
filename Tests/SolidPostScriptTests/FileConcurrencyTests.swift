//
//  FileConcurrencyTests.swift
//

import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct FileConcurrencyTests {

  @Test func dataFileConcurrentReadsConsumeEachByteOnce() async throws {
    let expected = Data((0..<128).map(UInt8.init))
    let file = DataFile(data: expected, mode: .read)

    let bytes = try await readConcurrently(from: file, count: expected.count)

    #expect(bytes.sorted() == Array(expected))
    try file.close()
    #expect(file.isClosed)
    #expect(throws: Error.ioError) {
      try file.readByte()
    }
  }

  @Test func osFileConcurrentReadsConsumeEachByteOnce() async throws {
    let expected = Data((0..<128).map(UInt8.init))
    let url = FileManager.default.temporaryDirectory
      .appending(path: "SolidPostScript-\(UUID().uuidString).bin")
    try expected.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let file = try OSFile(name: url.path, mode: .read, openMethod: .existingOnly)
    let bytes = try await readConcurrently(from: file, count: expected.count)

    #expect(bytes.sorted() == Array(expected))
    try file.close()
    #expect(file.isClosed)
    #expect(try file.readByte() == nil)
  }

  private func readConcurrently(from file: any File, count: Int) async throws -> [UInt8] {
    try await withThrowingTaskGroup(of: UInt8?.self, returning: [UInt8].self) { group in
      for _ in 0..<count {
        group.addTask { try file.readByte() }
      }

      var bytes: [UInt8] = []
      for try await byte in group {
        if let byte {
          bytes.append(byte)
        }
      }
      return bytes
    }
  }
}
