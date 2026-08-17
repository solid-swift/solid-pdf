//
//  FileAccessTests.swift
//

import Foundation
import SolidPostScript
import Testing

@Suite
struct FileAccessTests {

  @Test
  func objectFactoriesHonorAccess() throws {
    let file = DataFile(data: Data(), mode: .read)
    let fileObject = Object.file(file, access: .noAccess, vm: .local, kind: .literal)
    let dataFileObject = Object.dataFile(content: Data(), access: .executeOnly, vm: .local, kind: .literal)

    #expect(try fileObject.value(as: FileValue.self).access == .noAccess)
    #expect(try dataFileObject.value(as: FileValue.self).access == .executeOnly)
  }

  @Test
  func fileAndModeStringsRequireReadAccess() async throws {
    let url = temporaryURL()
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(url.path)) noaccess (r) file")
    }
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(url.path)) (r) noaccess file")
    }
  }

  @Test
  func readRequiresReadAccessButStatusDoesNot() async throws {
    let url = temporaryURL()
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(url.path)) (r) file noaccess read")
    }

    let status: BooleanValue = try await Interpreter.result(
      content: "(\(url.path)) (r) file noaccess status"
    )
    #expect(status.value)
  }

  @Test
  func statusReportsValidityRegardlessOfAccessOrDirection() async throws {
    let inputURL = temporaryURL()
    let outputURL = temporaryURL()
    try Data([1]).write(to: inputURL)
    defer {
      try? FileManager.default.removeItem(at: inputURL)
      try? FileManager.default.removeItem(at: outputURL)
    }

    let results = try await Interpreter.results(
      content: """
        /input (\(inputURL.path)) (r) file def
        /output (\(outputURL.path)) (w) file def
        /readwrite (\(inputURL.path)) (r+) file def
        /filtered (4869>) /ASCIIHexDecode filter def
        input noaccess status
        output executeonly status
        readwrite readonly status
        filtered noaccess status
        (%stdout) (w) file noaccess status
        /alias output def
        output closefile
        alias status
        """
    )

    let statuses = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(statuses == [false, true, true, true, true, true])
  }

  @Test
  func statusDoesNotRaiseAnAccessErrorThroughStopped() async throws {
    let results = try await Interpreter.results(
      content: "{ (%stdout) (w) file noaccess status } stopped"
    )
    let booleans = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(booleans == [false, true])
  }

  @Test
  func fileStringOperandsEnforceTheirAccess() async throws {
    let inputURL = temporaryURL()
    let outputURL = temporaryURL()
    try Data([1]).write(to: inputURL)
    defer {
      try? FileManager.default.removeItem(at: inputURL)
      try? FileManager.default.removeItem(at: outputURL)
    }

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(inputURL.path)) (r) file 1 string noaccess readstring")
    }
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(outputURL.path)) (w) file (a) noaccess writestring")
    }
  }

  @Test
  func writeRequiresWriteAccessAndUsesModulo256() async throws {
    let deniedURL = temporaryURL()
    let moduloURL = temporaryURL()
    defer {
      try? FileManager.default.removeItem(at: deniedURL)
      try? FileManager.default.removeItem(at: moduloURL)
    }

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(deniedURL.path)) (w) file readonly 65 write")
    }

    _ = try await Interpreter.execute(
      content: """
        (\(moduloURL.path)) (w) file
        dup -1 write dup 0 write dup 255 write dup 256 write dup 257 write
        closefile
        """
    )
    #expect(try Data(contentsOf: moduloURL) == Data([255, 0, 255, 0, 1]))
  }

  @Test
  func tokenAndExecutionUseTheirRespectiveAccess() async throws {
    let url = temporaryURL()
    try Data("/executed".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(url.path)) (r) file executeonly token")
    }

    let result: NameValue = try await Interpreter.result(
      content: "(\(url.path)) (r) file executeonly cvx exec"
    )
    #expect(result.value == "executed")

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(url.path)) (r) file noaccess cvx exec")
    }
  }

  @Test
  func accessNeutralOperationsRemainAvailable() async throws {
    let url = temporaryURL()
    try Data([1, 2, 3]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    _ = try await Interpreter.execute(
      content: "(\(url.path)) (r) file noaccess dup resetfile dup fileposition pop closefile"
    )
  }

  @Test
  func negativeFilePositionProducesRangeCheck() async throws {
    let url = temporaryURL()
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(content: "(\(url.path)) (r) file -1 setfileposition")
    }
  }

  @Test
  func invalidAccessUsesErrorDictionaryAndStopped() async throws {
    let url = temporaryURL()
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let results = try await Interpreter.results(
      content: "(\(url.path)) (r) file noaccess { read } stopped $error /errorname get"
    )
    #expect(results.contains { ($0.value as? NameValue)?.value == "invalidaccess" })
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SolidPostScript-\(UUID().uuidString).bin")
  }
}
