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
  func systemDictionaryPublishesTargetAndTypedMetadata() async throws {
    let languageLevel: IntegerValue = try await Interpreter.result(content: "languagelevel")
    let product: StringValue = try await Interpreter.result(content: "product")
    let version: StringValue = try await Interpreter.result(content: "version")
    let revision: IntegerValue = try await Interpreter.result(content: "revision")
    let serialNumber: IntegerValue = try await Interpreter.result(content: "serialnumber")

    #expect(languageLevel.value == 3)
    #expect(product.valueString == "SolidPostScript")
    #expect(product.access == .readOnly)
    #expect(product.vm == .global)
    #expect(version.valueString == "1")
    #expect(version.access == .readOnly)
    #expect(version.vm == .global)
    #expect(revision.value == 1)
    #expect(serialNumber.value == 0)

    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(content: "product 0 88 put")
    }
  }
}
