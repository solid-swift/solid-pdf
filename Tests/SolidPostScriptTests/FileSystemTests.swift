//
//  FileSystemTests.swift
//

import Foundation
import SolidPostScript
import Testing

@Suite
struct FileSystemTests {

  @Test
  func filenameStatusReturnsMetadataAndMissingReturnsFalse() async throws {
    let url = temporaryURL(extension: "dat")
    try Data(repeating: 0x41, count: 1_025).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let results = try await Interpreter.results(content: "(\(url.path)) status")
    #expect(results.count == 5)
    #expect(try results[0].value(as: IntegerValue.self).value == 2)
    #expect(try results[1].value(as: IntegerValue.self).value == 1_025)
    #expect(results[2].type == .integer)
    #expect(results[3].type == .integer)
    #expect(try results[4].value(as: BooleanValue.self).value)

    let missing = try await Interpreter.results(content: "(\(url.path).missing) status")
    #expect(missing.count == 1)
    #expect(try !missing[0].value(as: BooleanValue.self).value)
  }

  @Test
  func filenameStatusAcceptsDeviceNamesAndNullTermination() async throws {
    let url = temporaryURL(extension: "dat")
    try Data([1, 2, 3]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let deviceResults = try await Interpreter.results(content: "(%os%\(url.path)) status")
    #expect(try deviceResults.last?.value(as: BooleanValue.self).value == true)

    let nullResults = try await Interpreter.results(content: "(\(url.path)\\000ignored) status")
    #expect(try nullResults.last?.value(as: BooleanValue.self).value == true)
  }

  @Test
  func deleteAndRenameMutateTheExternalFileSystem() async throws {
    let source = temporaryURL(extension: "old")
    let destination = temporaryURL(extension: "new")
    try Data("content".utf8).write(to: source)
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }

    _ = try await Interpreter.execute(content: "(\(source.path)) (\(destination.path)) renamefile")
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(try Data(contentsOf: destination) == Data("content".utf8))

    _ = try await Interpreter.execute(content: "(\(destination.path)) deletefile")
    #expect(!FileManager.default.fileExists(atPath: destination.path))
  }

  @Test
  func fileSystemChangesSurviveRestore() async throws {
    let url = temporaryURL(extension: "dat")
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    _ = try await Interpreter.execute(content: "save (\(url.path)) deletefile restore")
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test
  func filenameForAllEnumeratesMatchesAndReusesTheScratchString() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appending(path: "a.ps")
    let second = directory.appending(path: "b.ps")
    let ignored = directory.appending(path: "c.txt")
    try Data().write(to: first)
    try Data().write(to: second)
    try Data().write(to: ignored)
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(try OSFileDevice.instance.fileNames(matching: "\(directory.path)/*.ps") == [first.path, second.path])

    let results = try await Interpreter.results(
      content: "(\(directory.path)/*.ps) { dup length string copy } 1024 string filenameforall"
    )
    let names = try results.map { try $0.value(as: StringValue.self).characters(in: 0..<$0.value(as: StringValue.self).count) }
      .compactMap { String(data: $0, encoding: .isoLatin1) }
    #expect(Set(names) == Set([first.path, second.path]))
  }

  @Test
  func filenameForAllHonorsDeviceTemplatesAndExit() async throws {
    let url = temporaryURL(extension: "ps")
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let template = "%*%\(url.deletingLastPathComponent().path)/*.ps"
    let results = try await Interpreter.results(content: "(\(template)) { exit } 1024 string filenameforall")
    #expect(results.count == 1)
    let result = try #require(results.first?.value as? StringValue)
    #expect(String(data: try result.characters(in: result.range), encoding: .isoLatin1) == "%os%\(url.path)")
  }

  @Test
  func operatingSystemTemplatesEscapeWildcardsAndDoNotCrossDirectories() throws {
    let directory = temporaryDirectory()
    let nested = directory.appending(path: "nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let oneCharacter = directory.appending(path: "a.ps")
    let twoCharacters = directory.appending(path: "ab.ps")
    let literalStar = directory.appending(path: "literal*name.ps")
    let nestedFile = nested.appending(path: "nested.ps")
    for url in [oneCharacter, twoCharacters, literalStar, nestedFile] { try Data().write(to: url) }
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(
      try Set(OSFileDevice.instance.fileNames(matching: "\(directory.path)/*.ps"))
        == Set([oneCharacter.path, twoCharacters.path, literalStar.path])
    )
    #expect(try OSFileDevice.instance.fileNames(matching: "\(directory.path)/?.ps") == [oneCharacter.path])
    #expect(
      try OSFileDevice.instance.fileNames(matching: "\(directory.path)/literal\\*name.ps") == [literalStar.path]
    )
  }

  @Test
  func filenameForAllPassesViewsOfTheSameScratchStorage() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appending(path: "a.ps")
    let second = directory.appending(path: "b.ps")
    try Data().write(to: first)
    try Data().write(to: second)
    defer { try? FileManager.default.removeItem(at: directory) }

    let stored: StringValue = try await Interpreter.result(
      content:
        """
        /stored null def /index 0 def
        (\(directory.path)/*.ps) {
          index 0 eq { /stored exch def } { pop } ifelse
          /index index 1 add store
        } 1024 string filenameforall
        stored
        """
    )
    #expect(String(data: try stored.characters(in: stored.range), encoding: .isoLatin1) == second.path)
  }

  @Test
  func relativeEnumerationUsesDeviceRegistrationOrder() async throws {
    let devices = FileDevices(devices: [
      ListingFileDevice(name: "first", fileNames: ["one.ps"]),
      ListingFileDevice(name: "second", fileNames: ["two.ps"]),
    ])
    let environment = InterpreterEnvironment(fileDevices: devices)

    let names: ArrayValue = try await Interpreter.result(
      content:
        """
        /names 2 array def /index 0 def
        (*) { names index 3 -1 roll dup length string copy put /index index 1 add store }
        32 string filenameforall
        names
        """,
      environment: environment
    )
    let values = try names.objects(in: names.range).compactMap { object -> String? in
      let string = try object.value(as: StringValue.self)
      return String(data: try string.characters(in: string.range), encoding: .isoLatin1)
    }
    #expect(values == ["one.ps", "two.ps"])
  }

  @Test
  func fileSystemOperandErrorsUsePostScriptErrors() async throws {
    let missing = temporaryURL(extension: "missing")
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: Error.undefinedFilename) {
      try await Interpreter.execute(content: "(\(missing.path)) deletefile")
    }
    await #expect(throws: Error.invalidFileAccess) {
      try await Interpreter.execute(content: "(%os%\(missing.path)) (%other%\(missing.path)) renamefile")
    }
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "(\(missing.path)) noaccess status")
    }
    await #expect(throws: Error.typeCheck) {
      try await Interpreter.execute(content: "(*) 1 10 string filenameforall")
    }
    await #expect(throws: Error.invalidFileAccess) {
      try await Interpreter.execute(content: "(%os%\(directory.path)) deletefile")
    }
    #expect(FileManager.default.fileExists(atPath: directory.path))
  }

  @Test
  func filenameForAllReportsSmallScratchThroughErrorDictionary() async throws {
    let url = temporaryURL(extension: "ps")
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let results = try await Interpreter.results(
      content: "{ (\(url.path)) { pop } 1 string filenameforall } stopped $error /errorname get"
    )
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
    #expect(results.contains { ($0.value as? NameValue)?.value == "rangecheck" })
  }

  private func temporaryURL(extension pathExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "SolidPostScript-\(UUID().uuidString)")
      .appendingPathExtension(pathExtension)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SolidPostScript-\(UUID().uuidString)")
  }
}

private struct ListingFileDevice: FileSystemDevice {
  let name: String
  let fileNames: [String]

  var searched: Bool { true }

  func open(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> any File {
    throw Error.undefinedFilename
  }

  func fileNames(matching template: String) throws -> [String] {
    fileNames
  }
}
