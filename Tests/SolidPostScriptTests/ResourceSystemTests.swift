import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct ResourceSystemTests {
  @Test
  func publishesEveryStandardCategoryWithItsPLRMType() async throws {
    let expected: [String: ObjectType] = [
      "Font": .dictionary, "CIDFont": .dictionary, "CMap": .dictionary,
      "FontSet": .dictionary, "Encoding": .array, "Form": .dictionary,
      "Pattern": .dictionary, "ProcSet": .dictionary, "ColorSpace": .array,
      "Halftone": .dictionary, "ColorRendering": .dictionary, "IdiomSet": .dictionary,
      "InkParams": .dictionary, "TrapParams": .dictionary, "OutputDevice": .dictionary,
      "ControlLanguage": .dictionary, "Localization": .dictionary, "PDL": .dictionary,
      "HWOptions": .dictionary, "Filter": .name, "ColorSpaceFamily": .name,
      "Emulator": .name, "IODevice": .string, "ColorRenderingType": .integer,
      "FMapType": .integer, "FontType": .integer, "FormType": .integer,
      "HalftoneType": .integer, "ImageType": .integer, "PatternType": .integer,
      "FunctionType": .integer, "ShadingType": .integer, "TrappingType": .integer,
      "Category": .dictionary,
    ]
    let environment = InterpreterEnvironment()

    for (name, type) in expected {
      let dictionary: DictionaryValue = try await Interpreter.result(
        content: "/\(name) /Category findresource",
        environment: environment
      )
      #expect(dictionary.vm == .global)
      #expect(dictionary.access == .readOnly)
      #expect(try dictionary.objectValue(forKey: "Category", as: NameValue.self).value == name)
      #expect(try dictionary.objectValue(forKey: "InstanceType", as: NameValue.self).value == type.name)
    }

    let generic: DictionaryValue = try await Interpreter.result(
      content: "/Generic /Category findresource",
      environment: environment
    )
    #expect(generic.vm == .global)
    #expect(try generic.object(forKeyIfExists: "InstanceType") == nil)
  }

  @Test
  func customCategoriesEnforceTypesAndLocalGlobalLifetime() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(content: defineWidgetCategory, environment: environment)

    let wrongType: NameValue = try await Interpreter.result(
      content: "{ /bad 1 /Widget defineresource } stopped pop $error /errorname get",
      environment: environment
    )
    #expect(wrongType.value == "typecheck")

    _ = try await Interpreter.execute(
      content: "true setglobal /shared (global) /Widget defineresource pop false setglobal",
      environment: environment
    )
    let shared: StringValue = try await Interpreter.result(
      content: "/shared /Widget findresource",
      environment: environment
    )
    #expect(shared.string == "global")
    #expect(shared.access == .readOnly)
    #expect(shared.vm == .global)

    let restored: BooleanValue = try await Interpreter.result(
      content:
        "save /saved exch def /temporary (local) /Widget defineresource pop saved restore /temporary /Widget resourcestatus not",
      environment: environment
    )
    #expect(restored.value)

    let localContext = try await Interpreter.execute(
      content: "/private (local) /Widget defineresource pop",
      environment: environment
    )
    let local: StringValue = try await localContext.peekOperandAfterExecuting("/private /Widget findresource")
    #expect(local.string == "local")

    let isolated: BooleanValue = try await Interpreter.result(
      content: "/private /Widget resourcestatus not",
      environment: environment
    )
    #expect(isolated.value)
  }

  @Test
  func restoreRevertsCompositesReachableOnlyThroughLocalResources() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        true setglobal
        /Generic /Category findresource dup length 1 add dict copy
        dup /InstanceType /dicttype put
        /Container exch /Category defineresource pop
        false setglobal
        /OnlyResource << /nested [1] >> /Container defineresource pop
        save /saved exch def
        /OnlyResource /Container findresource /nested get 0 2 put
        saved restore
        /OnlyResource /Container findresource /nested get 0 get 1 eq
        """
    )

    #expect(result.value)
  }

  @Test
  func persistentOuterRestoreRevertsGlobalResourceMappingsAndContents() async throws {
    let session = InterpreterSession()

    try await session.executeJob(
      content:
        """
        true () startjob pop
        true setglobal
        /Existing << /nested [1] >> /Generic defineresource pop
        /Removed 7 /Generic defineresource pop
        false setglobal
        save /saved exch def
        true setglobal
        /Existing /Generic findresource /nested get 0 2 put
        /Existing 9 /Generic defineresource pop
        /Added 3 /Generic defineresource pop
        /Removed /Generic undefineresource
        false setglobal
        saved restore
        /Existing /Generic findresource /nested get 0 get 1 ne {undefined} if
        /Removed /Generic findresource 7 ne {undefined} if
        /Added /Generic resourcestatus {pop pop undefined} if
        """
    )

    try await session.executeJob(
      content:
        """
        /Existing /Generic findresource /nested get 0 get 1 ne {undefined} if
        /Removed /Generic findresource 7 ne {undefined} if
        /Added /Generic resourcestatus {pop pop undefined} if
        """
    )
  }

  @Test
  func persistentOuterRestoreReinstatesReclaimedAutomaticResources() async throws {
    let environment = InterpreterEnvironment(resourceCategories: ["ProcSet": SyntheticProcSetResources.instance])
    let session = InterpreterSession(environment: environment)

    try await session.executeJob(
      content:
        """
        true () startjob pop
        /Synthetic /ProcSet findresource pop
        save /saved exch def
        2 vmreclaim
        /Synthetic /ProcSet resourcestatus {pop 2 ne {undefined} if} {undefined} ifelse
        saved restore
        /Synthetic /ProcSet resourcestatus {pop 1 ne {undefined} if} {undefined} ifelse
        """
    )
  }

  @Test
  func nestedPersistentSaveDoesNotRestoreGlobalResourcesBeforeTheOuterSave() async throws {
    let session = InterpreterSession()

    try await session.executeJob(
      content:
        """
        true () startjob pop
        save /outer exch def
        save /inner exch def
        true setglobal /Nested 1 /Generic defineresource pop false setglobal
        inner restore
        /Nested /Generic findresource 1 ne {undefined} if
        outer restore
        /Nested /Generic resourcestatus {pop pop undefined} if
        """
    )
  }

  @Test
  func restoringOneContextDoesNotReplaceALaterGlobalDefinition() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "true setglobal /Shared 1 /Generic defineresource pop false setglobal",
      environment: environment
    )
    let restoring = Context(environment: environment)
    let replacing = Context(environment: environment)
    let snapshot = try await restoring.snapshot(scope: .job)
    await restoring.registerLanguageSave(snapshot)

    try await restoring.executeResourceProgram(
      "true setglobal /Shared 2 /Generic defineresource pop false setglobal"
    )
    try await replacing.executeResourceProgram(
      "true setglobal /Shared 3 /Generic defineresource pop false setglobal"
    )
    try await restoring.restoreResourceSnapshot(snapshot)

    let value: IntegerValue = try await Interpreter.result(
      content: "/Shared /Generic findresource",
      environment: environment
    )
    #expect(value.value == 3)
  }

  @Test
  func resourceForAllCopiesPostScriptBytesRatherThanUTF8() async throws {
    let name = String(repeating: "é", count: 100)
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        \(defineWidgetCategory)
        /\(name) (value) /Widget defineresource pop
        /copiedLength 0 def
        (*) { /copiedLength exch length store } 100 string /Widget resourceforall
        copiedLength
        """
    )

    #expect(result.value == 100)
  }

  @Test
  func defaultResourceFileNamePreservesPostScriptPathBytes() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        \(defineWidgetCategory)
        << /GenericResourceDir (é/) /GenericResourcePathSep (/) >> setsystemparams
        /Widget /Category findresource begin
        /é 100 string ResourceFileName
        end
        0 get
        """
    )

    #expect(result.value == 0xE9)
  }

  @Test
  func genericStorageSupportsAliasesArbitraryKeysAndVMVisibility() async throws {
    let environment = InterpreterEnvironment()
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        \(defineWidgetCategory)
        /alias (aliased) /Widget defineresource pop
        7 (integer) /Widget defineresource pop
        true setglobal /shadow (global) /Widget defineresource pop
        false setglobal /shadow (local) /Widget defineresource pop
        /ok (alias) /Widget findresource (aliased) eq def
        /ok ok 7 /Widget findresource (integer) eq and def
        /ok ok /shadow /Widget findresource (local) eq and def
        /shadow /Widget undefineresource
        /ok ok /shadow /Widget findresource (global) eq and def
        /foundInteger false def
        (*) {
          dup type /integertype eq
          { 7 eq { /foundInteger true store } if }
          { pop }
          ifelse
        } 100 string /Widget resourceforall
        /shadow (second local) /Widget defineresource pop
        true setglobal /shadow /Widget undefineresource false setglobal
        ok foundInteger and /shadow /Widget resourcestatus not and
        """,
      environment: environment
    )
    #expect(result.value)
  }

  @Test
  func registeredValidationAndImplicitImmutabilityAreApplied() async throws {
    let environment = InterpreterEnvironment(resourceCategories: ["Validated": ValidatedResources.instance])
    let validationError: NameValue = try await Interpreter.result(
      content: "{ /bad (bad) /Validated defineresource } stopped pop $error /errorname get",
      environment: environment
    )
    #expect(validationError.value == "rangecheck")

    let accepted: StringValue = try await Interpreter.result(
      content: "/good (accepted) /Validated defineresource pop /good /Validated findresource",
      environment: environment
    )
    #expect(accepted.string == "accepted")

    let implicitError: NameValue = try await Interpreter.result(
      content: "{ /Extra /Extra /Filter defineresource } stopped pop $error /errorname get",
      environment: environment
    )
    #expect(implicitError.value == "invalidaccess")
  }

  @Test
  func syntheticProcSetProviderUsesAutomaticResourceLifecycle() async throws {
    let environment = InterpreterEnvironment(resourceCategories: ["ProcSet": SyntheticProcSetResources.instance])
    let before: BooleanValue = try await Interpreter.result(
      content: "/Synthetic /ProcSet resourcestatus { pop 2 eq } { false } ifelse",
      environment: environment
    )
    #expect(before.value)

    let dictionary: DictionaryValue = try await Interpreter.result(
      content: "/Synthetic /ProcSet findresource",
      environment: environment
    )
    #expect(try dictionary.objectValue(forKey: "answer", as: IntegerValue.self).value == 42)
    let payload = try dictionary.objectValue(forKey: "payload", as: ArrayValue.self)
    let nested = try payload.object(at: 0).value(as: StringValue.self)
    #expect(payload.allocation.membership(in: environment.globalVMAllocationSpace)?.isValid == true)
    #expect(nested.allocation.membership(in: environment.globalVMAllocationSpace)?.isValid == true)

    let after: BooleanValue = try await Interpreter.result(
      content: "/Synthetic /ProcSet resourcestatus { pop 1 eq } { false } ifelse",
      environment: environment
    )
    #expect(after.value)
  }

  @Test
  func externalFilesReportLoadEnumerateAndReclaim() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let widgetDirectory = root.appendingPathComponent("Widget", isDirectory: true)
    try FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
    try writeResource("A", body: "/A (automatic) /Widget defineresource pop", to: widgetDirectory, vmUsage: (12, 34))
    try writeResource("B", body: "/B (external) /Widget defineresource pop", to: widgetDirectory)

    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content:
        """
        \(defineWidgetCategory)
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        true setglobal /Explicit (explicit) /Widget defineresource pop false setglobal
        """,
      environment: environment
    )

    let external: BooleanValue = try await Interpreter.result(
      content: "/A /Widget resourcestatus { /size exch def /status exch def status 2 eq size 34 eq and } { false } ifelse",
      environment: environment
    )
    #expect(external.value)

    let loaded: StringValue = try await Interpreter.result(
      content: "/A /Widget findresource",
      environment: environment
    )
    #expect(loaded.string == "automatic")
    #expect(loaded.vm == .global)

    let automatic: BooleanValue = try await Interpreter.result(
      content: "/A /Widget resourcestatus { pop 1 eq } { false } ifelse",
      environment: environment
    )
    #expect(automatic.value)

    let names: ArrayValue = try await Interpreter.result(
      content:
        """
        /names 3 array def /index 0 def
        (*) { names index 3 -1 roll cvn put /index index 1 add def } 100 string /Widget resourceforall
        names
        """,
      environment: environment
    )
    let values = try names.objects(in: names.range).map { try $0.value(as: NameValue.self).value }
    #expect(values == ["Explicit", "A", "B"])

    let reclaimed: BooleanValue = try await Interpreter.result(
      content: "2 vmreclaim /A /Widget resourcestatus { pop 2 eq } { false } ifelse",
      environment: environment
    )
    #expect(reclaimed.value)
  }

  @Test
  func unknownCategoriesCanLoadFromCategoryResources() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let categoryDirectory = root.appendingPathComponent("Category", isDirectory: true)
    try FileManager.default.createDirectory(at: categoryDirectory, withIntermediateDirectories: true)
    try writeResource(
      "LoadedCategory",
      body:
        """
        true setglobal
        /Generic /Category findresource dup length 1 add dict copy
        dup /InstanceType /stringtype put
        /LoadedCategory exch /Category defineresource pop
        """,
      to: categoryDirectory
    )

    let environment = InterpreterEnvironment()
    let name: NameValue = try await Interpreter.result(
      content:
        """
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        /LoadedCategory /Category findresource /Category get
        """,
      environment: environment
    )
    #expect(name.value == "LoadedCategory")
  }

  @Test
  func failedExternalLoadsRollBackEveryPartialDefinition() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let widgetDirectory = root.appendingPathComponent("Widget", isDirectory: true)
    try FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
    try writeResource(
      "Missing",
      body: "/Leaked (partial) /Widget defineresource pop",
      to: widgetDirectory
    )

    let environment = InterpreterEnvironment()
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        \(defineWidgetCategory)
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        { /Missing /Widget findresource } stopped
        $error /errorname get /undefinedresource eq and
        /Leaked /Widget resourcestatus not and
        currentglobal not and
        """,
      environment: environment
    )
    #expect(result.value)
  }

  @Test
  func resourceOperatorRestoresStacksAfterImplementationFailure() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content:
        """
        true setglobal
        /Generic /Category findresource dup length 1 add dict copy
        dup /FindResource { 1 dict begin 99 doesnotexist } put
        /Broken exch /Category defineresource pop
        """,
      environment: environment
    )
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        false setglobal
        { /anything /Broken findresource } stopped
        count 3 eq
        countdictstack 3 eq and and
        exch pop exch pop
        """,
      environment: environment
    )
    #expect(result.value)
  }

  @Test
  func sharedEnvironmentAcceptsConcurrentGlobalDefinitions() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(content: defineWidgetCategory, environment: environment)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<16 {
        group.addTask {
          _ = try await Interpreter.execute(
            content: "true setglobal /K\(index) (\(index)) /Widget defineresource pop",
            environment: environment
          )
        }
      }
      try await group.waitForAll()
    }

    let count: IntegerValue = try await Interpreter.result(
      content:
        """
        /resourceCount 0 def
        (*) { pop /resourceCount resourceCount 1 add store } 100 string /Widget resourceforall
        resourceCount
        """,
      environment: environment
    )
    #expect(count.value == 16)
  }

  private var defineWidgetCategory: String {
    """
    true setglobal
    /Generic /Category findresource dup length 1 add dict copy
    dup /InstanceType /stringtype put
    /Widget exch /Category defineresource pop
    false setglobal
    """
  }

  private func temporaryResourceDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeResource(
    _ name: String,
    body: String,
    to directory: URL,
    vmUsage: (Int, Int)? = nil
  ) throws {
    var source = "%!PS\n"
    if let vmUsage { source += "%%VMusage: \(vmUsage.0) \(vmUsage.1)\n" }
    source += body + "\n"
    try Data(source.utf8).write(to: directory.appendingPathComponent(name))
  }
}

private enum ValidatedResources: ResourceCategory {
  case instance

  var dictionary: ResourceCategoryDictionary {
    .init(category: "Validated", instanceType: .string)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    ValidatedResourceExtension.instance
  }
}

private enum ValidatedResourceExtension: Operators.ResourceCategoryExtension {
  case instance

  func validateDefinition(key: Object, instance: Object, context: isolated Context) throws {
    guard try instance.value(as: StringValue.self).string != "bad" else { throw Error.rangeCheck }
  }
}

private enum SyntheticProcSetResources: ResourceCategory {
  case instance

  var dictionary: ResourceCategoryDictionary {
    .init(category: "ProcSet", instanceType: .dictionary)
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    try canonicalResourceKey(key) == "Synthetic" ? (false, 64) : nil
  }

  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
    guard try canonicalResourceKey(key) == "Synthetic" else { throw Error.undefinedResource }
    let payload = try Object.array(
      [.string("provider", access: .readOnly, vm: .global, kind: .literal)],
      access: .readOnly,
      vm: .global,
      kind: .literal
    )
    return try .dictionary(
      ["answer": 42, "payload": payload],
      access: .unlimited,
      vm: .global,
      kind: .literal
    )
  }
}

private extension Context {
  func executeResourceProgram(_ content: String) async throws {
    let file = DataFile(data: try LanguageLimits.postScriptBytes(content), mode: .read)
    try await pushAndRun(source: .file(file, access: .readOnly, vm: .local, kind: .executable))
  }

  func restoreResourceSnapshot(_ snapshot: Snapshot) throws {
    try snapshot.restore(to: self)
  }

  func peekOperandAfterExecuting(_ content: String) async throws -> StringValue {
    let file = DataFile(data: Data(content.utf8), mode: .read)
    try await pushAndRun(source: .file(file, access: .readOnly, vm: .local, kind: .executable))
    return try peekOperand().value(as: StringValue.self)
  }
}
