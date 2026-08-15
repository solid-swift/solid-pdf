//
//  OSFileTests.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation
import SolidCore
import SolidPostScript
import Testing


@Suite
struct OSFileTests {

  @Test
  func testOpen() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (w) file")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual((res1[0].value as? FileValue)?.name, file)
    expectEqual((res1[0].value as? FileValue)?.mode, .write)
    expectEqual((res1[0].value as? FileValue)?.file.isClosed, false)
  }

  @Test
  func testOpenStd() async throws {
    let res1 = try await Interpreter.results(content: "(%stdin) (r) file")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual((res1[0].value as? FileValue)?.name, "stdin")
    expectEqual((res1[0].value as? FileValue)?.mode, .read)

    let res2 = try await Interpreter.results(content: "(%stdout) (w) file")
    expectEqual(res2.count, 1)
    expectEqual(res2[0].type, .file)
    expectEqual((res2[0].value as? FileValue)?.name, "stdout")
    expectEqual((res2[0].value as? FileValue)?.mode, .write)

    let res3 = try await Interpreter.results(content: "(%stderr) (w) file")
    expectEqual(res3.count, 1)
    expectEqual(res3[0].type, .file)
    expectEqual((res3[0].value as? FileValue)?.name, "stderr")
    expectEqual((res3[0].value as? FileValue)?.mode, .write)
  }

  @Test
  func testClose() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (w) file dup closefile")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual((res1[0].value as? FileValue)?.name, file)
    expectEqual((res1[0].value as? FileValue)?.mode, .write)
    expectEqual((res1[0].value as? FileValue)?.file.isClosed, true)
  }

  @Test
  func testRead() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([26, 28, 30]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file read")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .integer)
    expectEqual((res1[0].value as? IntegerValue)?.value, 26)
    expectEqual(res1[1].type, .boolean)
    expectEqual((res1[1].value as? BooleanValue)?.value, true)
  }

  @Test
  func testReadEOF() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file dup read")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .file)
    expectEqual((res1[1].value as? FileValue)?.file.isClosed, true)
  }

  @Test
  func testReadString() async throws {
    let data = Data([26, 28, 30])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 3 string readstring")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, true)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 3)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<3), data)
  }

  @Test
  func testReadStringEOF() async throws {
    let data = Data([26, 28, 30])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 10 string readstring")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 3)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<3), data)
  }

  @Test
  func testReadHexString() async throws {
    let data = Data([26, 28, 30])
    let hexData = Data([49, 10, 97, 0, 49, 99, 32, 49, 101])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: hexData)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 3 string readhexstring")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, true)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 3)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<3), data)
  }

  @Test
  func testReadHexStringEOF() async throws {
    let data = Data([26, 28, 30])
    let hexData = Data([49, 10, 97, 0, 49, 99, 32, 49, 101, 0])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: hexData)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 10 string readhexstring")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 3)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<3), data)
  }

  @Test
  func testReadLine() async throws {
    let data = "Hello\nWorld!".data(using: .ascii)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 10 string readline")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, true)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 5)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<5), data[0..<5])
  }

  @Test
  func testReadLineCRLF() async throws {
    let data = "Hello\r\nWorld!".data(using: .ascii)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(
      content: "(\(file)) (r) file dup 10 string readline 2 index 10 string readline"
    )
    expectEqual(res1.count, 5)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 6)
    expectEqual((res1[1].value as? StringValue)?.valueString, "World!")
    expectEqual(res1[2].type, .boolean)
    expectEqual((res1[2].value as? BooleanValue)?.value, true)
    expectEqual(res1[3].type, .string)
    expectEqual((res1[3].value as? StringValue)?.count, 5)
    expectEqual((res1[3].value as? StringValue)?.valueString, "Hello")
  }

  @Test
  func testReadLineLFCR() async throws {
    let data = "Hello\n\rWorld!".data(using: .ascii)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let ps = "(\(file)) (r) file dup 10 string readline 2 index 10 string readline 4 index 10 string readline"
    let res1 = try await Interpreter.results(content: ps)
    expectEqual(res1.count, 7)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 6)
    expectEqual((res1[1].value as? StringValue)?.valueString, "World!")
    expectEqual(res1[2].type, .boolean)
    expectEqual((res1[2].value as? BooleanValue)?.value, true)
    expectEqual(res1[3].type, .string)
    expectEqual((res1[3].value as? StringValue)?.count, 0)
    expectEqual((res1[3].value as? StringValue)?.valueString, "")
    expectEqual(res1[4].type, .boolean)
    expectEqual((res1[4].value as? BooleanValue)?.value, true)
    expectEqual(res1[5].type, .string)
    expectEqual((res1[5].value as? StringValue)?.count, 5)
    expectEqual((res1[5].value as? StringValue)?.valueString, "Hello")
  }

  @Test
  func testReadLineEOF() async throws {
    let data = "Hello".data(using: .ascii)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 10 string readline")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, false)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 5)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<5), data[0..<5])
  }

  @Test
  func testReadLineLFEOF() async throws {
    let data = "Hello\n".data(using: .ascii)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: data)
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file 10 string readline")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, true)
    expectEqual(res1[1].type, .string)
    expectEqual((res1[1].value as? StringValue)?.count, 5)
    expectEqual(try (res1[1].value as? StringValue)?.characters(in: 0..<5), data[0..<5])
  }

  @Test
  func testWrite() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (a+) file dup 111 write")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.size, 1)
  }

  @Test
  func testWriteString() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = fileURL.path()
    FileManager.default.createFile(atPath: file, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (a+) file dup (abcde) writestring")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.size, 5)
    expectEqual(try String(contentsOf: fileURL, encoding: .utf8), "abcde")
  }

  @Test
  func testWriteHexString() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = fileURL.path()
    FileManager.default.createFile(atPath: file, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (a+) file dup (abcde) writehexstring")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.size, 10)
    expectEqual(
      try Data(contentsOf: fileURL),
      "abcde".data(using: .ascii).map { Data($0.baseEncoded(using: .base16Lower).utf8) }
    )
  }

  @Test
  func testBytesAvailable() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([1, 2, 3, 4, 5]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file dup bytesavailable")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .integer)
    expectEqual((res1[0].value as? IntegerValue)?.value, 5)
    expectEqual(res1[1].type, .file)
    expectEqual(try (res1[1].value as? FileValue)?.file.size, 5)
  }

  @Test
  func testFlush() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (w) file dup (abcde) writestring dup flushfile")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.size, 5)
  }

  @Test
  func testReset() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (w) file dup (abcde) writestring dup resetfile")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.size, 5)
  }

  @Test
  func testStatus() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (w) file dup status")
    expectEqual(res1.count, 2)
    expectEqual(res1[0].type, .boolean)
    expectEqual((res1[0].value as? BooleanValue)?.value, true)
    expectEqual(res1[1].type, .file)
    expectEqual((res1[1].value as? FileValue)?.file.isClosed, false)

    let res2 = try await Interpreter.results(content: "(\(file)) (w) file dup closefile dup status")
    expectEqual(res2.count, 2)
    expectEqual(res2[0].type, .boolean)
    expectEqual((res2[0].value as? BooleanValue)?.value, false)
    expectEqual(res2[1].type, .file)
    expectEqual((res2[1].value as? FileValue)?.file.isClosed, true)
  }

  @Test
  func testGetPosition() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([1, 2, 3, 4, 5]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file dup read pop pop fileposition")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .integer)
    expectEqual((res1[0].value as? IntegerValue)?.value, 1)
  }

  @Test
  func testSetPosition() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: Data([1, 2, 3, 4, 5]))
    defer { try? FileManager.default.removeItem(atPath: file) }

    let res1 = try await Interpreter.results(content: "(\(file)) (r) file dup 3 setfileposition")
    expectEqual(res1.count, 1)
    expectEqual(res1[0].type, .file)
    expectEqual(try (res1[0].value as? FileValue)?.file.offset, 3)
  }

  @Test
  func testToken() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: "abc def ghi".data(using: .isoLatin1).neverNil())
    defer { try? FileManager.default.removeItem(atPath: file) }

    typealias Result = (BooleanValue, NameValue, NameValue)
    let ps = "(\(file)) (r) file dup token pop exch token"
    let (result, token2, token) = try await Interpreter.result(content: ps, as: Result.self)
    expectEqual(result.value, true)
    expectEqual(token2.value, "def")
    expectEqual(token.value, "abc")
  }

  @Test
  func testExec() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: "/abc /def /ghi".data(using: .isoLatin1).neverNil())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let ps = "(\(file)) (r) file cvx exec"
    let names = try await Interpreter.result(content: ps, count: 3, as: NameValue.self)
    expectEqual(names.count, 3)
    expectEqual(names[0].value, "ghi")
    expectEqual(names[1].value, "def")
    expectEqual(names[2].value, "abc")
  }

  @Test
  func testRunFile() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path()
    FileManager.default.createFile(atPath: file, contents: "/abc /def /ghi".data(using: .isoLatin1).neverNil())
    defer { try? FileManager.default.removeItem(atPath: file) }

    let ps = "(\(file)) run"
    let names = try await Interpreter.result(content: ps, count: 3, as: NameValue.self)
    expectEqual(names.count, 3)
    expectEqual(names[0].value, "ghi")
    expectEqual(names[1].value, "def")
    expectEqual(names[2].value, "abc")
  }

}
