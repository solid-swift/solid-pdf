//
//  MigrationTests.swift
//  SolidPDF
//
//  Created by Kevin Wooten on 8/15/26.
//

import SolidPostScript
import Testing

@Suite
struct MigrationTests {

  @Test
  func publicInterpreterEntryPointsRemainAvailable() async throws {
    let context = try await Interpreter.execute(content: "10 20 add")
    let contextResults = try await context.results()
    #expect(try contextResults.first?.value(as: IntegerValue.self).value == 30)

    let results = try await Interpreter.results(content: "1 2")
    #expect(results.count == 2)

    let tuple: (IntegerValue, IntegerValue) = try await Interpreter.result(content: "1 2")
    #expect(tuple.0.value == 2)
    #expect(tuple.1.value == 1)

    let counted: [IntegerValue] = try await Interpreter.result(content: "1 2", count: 2)
    #expect(counted.map(\.value) == [2, 1])
  }

  @Test
  func systemDictionaryUsesSolidPostScriptProductName() async throws {
    let product: NameValue = try await Interpreter.result(content: "product")

    #expect(product.value == "SolidPostScript")
  }
}
