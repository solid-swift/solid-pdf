//
//  NameVMTests.swift
//

import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct NameVMTests {

  @Test
  func languageNamesAreChargedOnceInGlobalVM() async throws {
    let environment = InterpreterEnvironment()
    let context = Context(environment: environment)
    let name = "name_\(UUID().uuidString)"
    let before = environment.globalVMAllocationSpace.chargedBytes

    try await context.executeNameProgram("/\(name) (\(name)) cvn")
    let afterFirstUse = environment.globalVMAllocationSpace.chargedBytes
    await context.clearNameTestOperands()
    try await context.executeNameProgram("/\(name) (\(name)) cvn")

    #expect(afterFirstUse - before == name.utf8.count + 24)
    #expect(environment.globalVMAllocationSpace.chargedBytes == afterFirstUse)
  }

  @Test
  func nameAccountingSurvivesJobRestoreAndCollection() async throws {
    let environment = InterpreterEnvironment()
    let context = Context(environment: environment)
    let snapshot = try await context.snapshot(scope: .job)
    await context.registerLanguageSave(snapshot)
    let name = "post_save_\(UUID().uuidString)"

    try await context.executeNameProgram("/\(name)")
    let charged = environment.globalVMAllocationSpace.chargedBytes
    try await context.restoreNameTestSnapshot(snapshot)
    environment.globalVMAllocationSpace.collectCycles()
    _ = environment.nameTable.intern(name)

    #expect(environment.globalVMAllocationSpace.chargedBytes == charged)
  }

  @Test
  func environmentsOwnIndependentConcurrentNameTables() async throws {
    let first = InterpreterEnvironment()
    let second = InterpreterEnvironment()
    let name = "concurrent_\(UUID().uuidString)"
    let firstBefore = first.globalVMAllocationSpace.chargedBytes
    let secondBefore = second.globalVMAllocationSpace.chargedBytes

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<50 {
        group.addTask {
          _ = first.nameTable.intern(name)
        }
      }
    }
    _ = second.nameTable.intern(name)

    let expectedCharge = name.utf8.count + 24
    #expect(first.globalVMAllocationSpace.chargedBytes - firstBefore == expectedCharge)
    #expect(second.globalVMAllocationSpace.chargedBytes - secondBefore == expectedCharge)
  }
}

private extension Context {
  func executeNameProgram(_ content: String) async throws {
    let file = DataFile(data: Data(content.utf8), mode: .read)
    try await pushAndRun(source: .file(file, access: .readOnly, vm: .local, kind: .executable))
  }

  func clearNameTestOperands() {
    operands = OperandStack()
  }

  func restoreNameTestSnapshot(_ snapshot: Snapshot) throws {
    try snapshot.restore(to: self)
  }
}
