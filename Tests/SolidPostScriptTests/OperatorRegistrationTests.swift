//
//  OperatorRegistrationTests.swift
//

import Testing

@testable import SolidPostScript

@Suite
struct OperatorRegistrationTests {

  @Test
  func registersCurrentFileAndResourceOperators() async throws {
    let systemDictionary: DictionaryValue = try await Interpreter.result(content: "systemdict")

    #expect(
      try systemDictionary.objectValue(forKey: "currentfile", as: Operators.CurrentFile.self)
        == Operators.CurrentFile.instance
    )
    for name in ["defineresource", "undefineresource", "findresource", "resourcestatus", "resourceforall"] {
      #expect(try systemDictionary.object(forKey: .literalName(name)).value is Operators.ResourceOperator)
    }
  }

  @Test
  func currentFileReturnsLiteralExecutionFile() async throws {
    let results = try await Interpreter.results(content: "currentfile")
    #expect(results.count == 1)
    #expect(results.first?.kind == .literal)
    let file = try #require(results.first?.value as? FileValue)
    #expect(!file.file.isClosed)
  }

  @Test
  func currentFileReturnsClosedFileWithoutExecutionFile() async throws {
    let context = Context()
    try await Operators.CurrentFile.instance.execute(context: context)

    let currentFile = try await context.peekOperand()
    #expect(currentFile.kind == .literal)
    #expect(try currentFile.value(as: FileValue.self).file.isClosed)
  }

  @Test
  func unsupportedResourceCategoryRemainsUndefined() async throws {
    await #expect(throws: Error.undefined) {
      try await Interpreter.execute(content: "/key /MissingCategory findresource")
    }
  }
}
