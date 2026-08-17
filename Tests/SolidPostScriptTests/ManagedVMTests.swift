//
//  ManagedVMTests.swift
//

import Foundation
@testable import SolidPostScript
import Synchronization
import Testing

@Suite
struct ManagedVMTests {

  @Test
  func weakLedgerRetainsChargesUntilCollection() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    var object: Object? = try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      try .array([.integer(1)], access: .unlimited, vm: .local, kind: .literal)
    }

    let charged = local.chargedBytes
    #expect(charged > 0)
    object = nil
    #expect(local.chargedBytes == charged)

    local.pruneWeakGarbage()
    #expect(local.chargedBytes == 0)
    _ = object
  }

  @Test
  func disabledAutomaticReclamationDoesNotPruneWeakGarbage() {
    let local = VMAllocationSpace(vm: .local)
    var allocation: VMAllocation? = local.allocate(bytes: 32)
    allocation = nil

    #expect(!local.prepareForAllocation(bytes: 1, maximum: 32, automaticCollection: false, threshold: 0))
    #expect(local.chargedBytes == 32)

    local.pruneWeakGarbage()
    #expect(local.prepareForAllocation(bytes: 1, maximum: 32, automaticCollection: false, threshold: 0))
    _ = allocation
  }

  @Test
  func detachedCompositeAdoptionHonorsMaxLocalVM() async throws {
    let object = try Object.array([.null], access: .unlimited, vm: .local, kind: .literal)
    let allocation = try object.value(as: ArrayValue.self).allocation
    let context = Context()

    await #expect(throws: Error.vmError) {
      try await context.adoptAtCurrentLocalVMLimit(object)
    }
    let local = await context.localVMAllocationSpace
    #expect(allocation.membership(in: local) == nil)
  }

  @Test
  func fileCreationPreflightsBeforeOpeningTheDevice() async throws {
    let device = CountingFileDevice()
    let context = Context(fileDevices: FileDevices(devices: [device]))

    await #expect(throws: Error.vmError) {
      try await context.openFileAtCurrentLocalVMLimit()
    }
    #expect(device.openCount == 0)
  }

  @Test
  func saveCreationHonorsMaxLocalVMTransactionally() async throws {
    let context = Context()

    await #expect(throws: Error.vmError) {
      try await context.saveAtCurrentLocalVMLimit()
    }
    #expect(await context.saveDepth == 0)
  }

  @Test
  func fullCollectionBreaksSelfAndMutualCycles() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    var roots: [Object] = try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      let first = try Object.array([.null], access: .unlimited, vm: .local, kind: .literal)
      let second = try Object.array([.null], access: .unlimited, vm: .local, kind: .literal)
      let firstArray = try first.value(as: ArrayValue.self)
      let secondArray = try second.value(as: ArrayValue.self)
      try firstArray.updateObject(second, at: 0)
      try secondArray.updateObject(first, at: 0)
      return [first, second]
    }

    #expect(local.chargedBytes > 0)
    roots.removeAll()
    local.collectCycles()
    #expect(local.chargedBytes == 0)
  }

  @Test
  func fullCollectionBreaksMixedArrayDictionaryCycles() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    var roots: [Object] = try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      let array = try Object.array([.null], access: .unlimited, vm: .local, kind: .literal)
      let dictionary = try Object.dictionary([:], access: .unlimited, vm: .local, kind: .literal)
      try array.value(as: ArrayValue.self).updateObject(dictionary, at: 0)
      try dictionary.value(as: DictionaryValue.self).updateObject(array, forKey: "array")
      return [array, dictionary]
    }

    roots.removeAll()
    local.collectCycles()
    #expect(local.chargedBytes == 0)
  }

  @Test
  func reachableCyclesAndHostResultsRemainAlive() async throws {
    let context = try await Interpreter.execute(
      content: "/a 1 array def a 0 a put a"
    )
    let results = try await context.results()
    let result = results[0]
    let array = try result.value(as: ArrayValue.self)

    let space = await context.localVMAllocationSpace
    space.collectCycles()

    let child = try array.object(at: 0)
    #expect(child == result)
  }

  @Test
  func contextDestructionCollectsUnreturnedCycles() async throws {
    weak var releasedSpace: VMAllocationSpace?
    do {
      let space = try await makeCyclicContextSpace()
      releasedSpace = space
    }

    for _ in 0..<20 where releasedSpace != nil {
      await Task.yield()
    }

    #expect(releasedSpace == nil)
  }

  private func makeCyclicContextSpace() async throws -> VMAllocationSpace {
    let context = try await Interpreter.execute(content: "/a 1 array def a 0 a put")
    return await context.localVMAllocationSpace
  }

  @Test
  func aliasesAndIntervalsChargeOneBacking() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    let objects = try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      let array = try Object.array([.null, .null], access: .unlimited, vm: .local, kind: .literal)
      let value = try array.value(as: ArrayValue.self)
      let interval = try Object.array(sharing: value, subRange: 0..<1, kind: .literal)
      return [array, interval]
    }

    #expect(local.chargedBytes == 32)
    #expect(objects[0] != objects[1])
  }

  @Test
  func dictionaryCapacityGrowthUsesItsActualBackingCharge() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      let dictionary = try DictionaryValue(value: [:], access: .unlimited, vm: .local)
      let before = local.chargedBytes
      let source = try DictionaryValue(
        value: Dictionary(uniqueKeysWithValues: (0..<20).map { (Object.integer(Int32($0)), Object.null) }),
        access: .unlimited,
        vm: .local
      )
      let sourceCharge = local.chargedBytes - before
      let mutation = try dictionary.prepareUpdateObjects(forKeysIn: source)

      #expect(try dictionary.commit(mutation))
      #expect(local.chargedBytes - before - sourceCharge == mutation.allocationGrowthBytes)
      #expect(dictionary.capacity >= dictionary.count)
    }
  }

  @Test
  func localEdgesKeepGlobalAllocationsReachable() throws {
    let local = VMAllocationSpace(vm: .local)
    let global = VMAllocationSpace(vm: .global)
    var root: Object? = try VMAllocationContext.$spaces.withValue(.init(local: local, global: global)) {
      let globalObject = try Object.array([.integer(1)], access: .unlimited, vm: .global, kind: .literal)
      return try Object.array([globalObject], access: .unlimited, vm: .local, kind: .literal)
    }

    global.collectCycles()
    do {
      let retained = try root?.value(as: ArrayValue.self).object(at: 0).value(as: ArrayValue.self)
      #expect(try retained?.object(at: 0) == .integer(1))
    }

    root = nil
    local.collectCycles()
    global.collectCycles()
    #expect(local.chargedBytes == 0)
    #expect(global.chargedBytes == 0)
  }

  @Test
  func saveStateKeepsOtherwiseHiddenCyclesReachable() async throws {
    let restored: BooleanValue = try await Interpreter.result(
      content:
        """
        /a 1 array def a 0 a put
        save /s exch def
        userdict /a undef
        1 vmreclaim
        s restore
        a dup 0 get eq
        """
    )

    #expect(restored.value)
  }

  @Test
  func discardedSaveStateReclaimsCapturedCyclesInOnePass() async throws {
    let context = try await Interpreter.execute(
      content:
        """
        /a 1 array def a 0 a put
        save /s exch def
        userdict /a undef
        userdict /s undef
        """
    )
    let space = await context.localVMAllocationSpace
    let before = space.chargedBytes

    space.collectCycles()
    let afterFirstCollection = space.chargedBytes
    space.collectCycles()

    #expect(afterFirstCollection < before)
    #expect(space.chargedBytes == afterFirstCollection)
  }

  @Test
  func vmReclaimModesAndVMErrorSnapshots() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /sentinelO [1] def /sentinelE [2] def /sentinelD [3] def
        /allocate { 10 string } def
        $error /ostack sentinelO put
        $error /estack sentinelE put
        $error /dstack sentinelD put
        << /MaxLocalVM 1 /VMReclaim -1 >> setuserparams
        /allocate load stopped clear
        $error /errorname get
        $error /dstack get
        $error /estack get
        $error /ostack get
        """,
    )
    let operandSnapshot = results[0]
    let executionSnapshot = results[1]
    let dictionarySnapshot = results[2]
    let errorName = try results[3].value(as: NameValue.self)

    #expect(errorName.value == "VMerror")
    #expect(try operandSnapshot.value(as: ArrayValue.self).object(at: 0) == .integer(1))
    #expect(try executionSnapshot.value(as: ArrayValue.self).object(at: 0) == .integer(2))
    #expect(try dictionarySnapshot.value(as: ArrayValue.self).object(at: 0) == .integer(3))
  }

  @Test
  func packedArrayAllocationHonorsMaxLocalVMTransactionally() async throws {
    let results = try await Interpreter.results(
      content:
        """
        /operation { 1 2 3 3 packedarray } def
        << /MaxLocalVM 1 /VMReclaim -1 >> setuserparams
        /operation load stopped
        $error /command get /packedarray load eq
        $error /errorname get
        """
    )

    #expect(try results[0].value(as: NameValue.self).value == "VMerror")
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: BooleanValue.self).value)
    #expect(results[3].value is Operators.ConstructPackedArray)
    #expect(try results[4].value(as: IntegerValue.self).value == 3)
    #expect(try results[5].value(as: IntegerValue.self).value == 3)
    #expect(try results[6].value(as: IntegerValue.self).value == 2)
    #expect(try results[7].value(as: IntegerValue.self).value == 1)
  }

  @Test
  func parameterDictionariesPreflightRetainedStrings() async throws {
    let context = Context()

    await #expect(throws: Error.vmError) {
      try await context.constructParameterDictionaryAtDictionaryOnlyLimit()
    }
  }
}

private extension Context {
  func adoptAtCurrentLocalVMLimit(_ object: Object) throws {
    userParameters.setInteger(Int32(localVMAllocationSpace.chargedBytes), for: "MaxLocalVM")
    userParameters.setInteger(-1, for: "VMReclaim")
    try adopt(object)
  }

  func openFileAtCurrentLocalVMLimit() throws {
    userParameters.setInteger(Int32(localVMAllocationSpace.chargedBytes), for: "MaxLocalVM")
    userParameters.setInteger(-1, for: "VMReclaim")
    _ = try openFileObject(name: "%counting%input", mode: "r")
  }

  func saveAtCurrentLocalVMLimit() async throws {
    userParameters.setInteger(Int32(localVMAllocationSpace.chargedBytes), for: "MaxLocalVM")
    userParameters.setInteger(-1, for: "VMReclaim")
    try await Operators.Save.instance.execute(context: self)
  }

  func constructParameterDictionaryAtDictionaryOnlyLimit() throws {
    let values = ["Retained": ParameterValue.string(Data(repeating: 0, count: 64))]
    let dictionaryBytes = estimatedAllocationSize(count: values.count, objectType: .dictionary)
    let maximum = localVMAllocationSpace.chargedBytes + dictionaryBytes
    userParameters.setInteger(Int32(maximum), for: "MaxLocalVM")
    userParameters.setInteger(-1, for: "VMReclaim")

    _ = try parameterDictionary(values)
  }
}

private final class CountingFileDevice: FileDevice, Sendable {
  let name = "counting"
  let searched = false
  private let state = Mutex<Int>(0)

  var openCount: Int { state.withLock { $0 } }

  func open(name: String, mode: FileMode, openMethod: FileOpenMethod) throws -> any File {
    state.withLock { $0 += 1 }
    return DataFile(data: Data(), mode: .read)
  }
}
