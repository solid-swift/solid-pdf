import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct IdiomRecognitionTests {

  @Test
  func bindPreservesIdentityAndUnresolvedNames() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        /procedure { doesnotexist 1 2 add } def
        /procedure load dup bind eq
        /procedure load 0 get /doesnotexist eq and
        /procedure load 3 get type /operatortype eq and
        """
    )
    #expect(result.value)
  }

  @Test
  func bindIgnoresReadOnlyArraysAndBindsPackedArraysInPlace() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        /ordinary { 1 2 add } readonly def
        /ordinary load dup bind eq
        /ordinary load 2 get type /nametype eq and
        true setpacking
        /packed { 1 2 add } def
        /packed load dup bind eq and
        /packed load 2 get type /operatortype eq and
        """
    )
    #expect(result.value)
  }

  @Test
  func bindDoesNotRecognizeReadOnlyOrdinaryArrays() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /Set << /entry [ { 1 } bind { 42 } bind ] >> /IdiomSet defineresource pop
        /candidate { 1 } readonly def
        << /IdiomRecognition true >> setuserparams
        /candidate load bind exec
        """
    )
    #expect(result.value == 1)
  }

  @Test
  func bindMakesNestedProceduresReadOnly() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        /procedure { 1 { 2 3 add } } def
        /procedure load bind pop
        /procedure load 1 get
        dup rcheck exch wcheck not and
        """
    )
    #expect(result.value)
  }

  @Test
  func bindUpdatesOnlyTheSelectedOrdinaryArrayInterval() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        /full { before 1 2 add after } def
        /interval /full load 1 3 getinterval def
        /interval load dup bind eq
        /full load 3 get type /operatortype eq and
        /full load 0 get type /nametype eq and
        /full load 4 get type /nametype eq and
        """
    )
    #expect(result.value)
  }

  @Test
  func bindDistinguishesPackedIntervalsSharingOneBacking() async throws {
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        true setpacking
        /base { 1 2 add 3 4 sub } def
        /first /base load 0 3 getinterval def
        /second /base load 3 3 getinterval def
        false setpacking
        /outer 2 array cvx def
        /outer load 0 /first load put
        /outer load 1 /second load put
        /outer load bind pop
        /outer load 0 get /outer load 1 get ne
        /outer load 0 get 2 get type /operatortype eq and
        /outer load 1 get 2 get type /operatortype eq and
        """
    )
    #expect(result.value)
  }

  @Test
  func packedArrayIdentityAndBindingParticipateInRestore() async throws {
    let identity: [BooleanValue] = try await Interpreter.result(
      content: "1 1 packedarray dup eq 1 1 packedarray 1 1 packedarray eq",
      count: 2
    )
    #expect(identity.map(\.value) == [false, true])

    let restored: BooleanValue = try await Interpreter.result(
      content:
        """
        true setpacking
        /procedure { 1 2 add } def
        save /saved exch def
        /procedure load bind pop
        saved restore
        /procedure load 2 get type /nametype eq
        """
    )
    #expect(restored.value)
  }

  @Test
  func bindTerminatesForRecursiveArrays() async throws {
    let context = Context()
    let array = try ArrayValue(elements: [.null], access: .unlimited, vm: .local)
    let procedure = Object(value: array, kind: .executable)
    try array.updateObject(procedure, at: 0)

    let bound = try await Operators.Bind.instance.bind(context: context, array: array)
    #expect(bound == procedure)
    #expect(try array.object(at: 0) == procedure)
  }

  @Test
  func idiomsUsePostScriptEqualityAndIgnoreArrayRepresentations() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        true setpacking /template { 4.0 (answer) { 1 2 add } } bind def
        false setpacking /substitute { 42 } bind def
        /Set << /mixed [ /template load /substitute load ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        { 4 /answer { 1 2 add } } bind exec
        """
    )
    #expect(result.value == 42)
  }

  @Test
  func idiomRecognitionComparesOnlySelectedProcedureIntervals() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /templateBacking { templatePrefix 1 2 add templateSuffix } def
        /template /templateBacking load 1 3 getinterval bind def
        /substitute { 42 } bind def
        /Set << /entry [ /template load /substitute load ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        /candidateBacking { candidatePrefix 1 2 add candidateSuffix } def
        /candidate /candidateBacking load 1 3 getinterval def
        /candidate load bind exec
        """
    )
    #expect(result.value == 42)
  }

  @Test
  func idiomMatchingIgnoresNestedExecutionAndAccessAttributes() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /template 1 array cvx def
        /template load 0 { 1 } cvlit readonly put
        /substitute { 77 } bind def
        /Set << /entry [ /template load /substitute load ] >> /IdiomSet defineresource pop
        /nested { 1 } noaccess def
        /candidate 1 array cvx def
        /candidate load 0 /nested load put
        << /IdiomRecognition true >> setuserparams
        /candidate load bind exec
        """
    )
    #expect(result.value == 77)
  }

  @Test
  func nestedSubstitutionsHappenBeforeEnclosingMatches() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /Set <<
          /inner [ { 1 2 add } bind { 7 } bind ]
          /outer [ { { 7 } } bind { 99 } bind ]
        >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        { { 1 2 add } } bind exec
        """
    )
    #expect(result.value == 99)
  }

  @Test(arguments: [(9, true), (10, true), (11, false)])
  func idiomComparisonStopsAfterTenArrayLevels(depth: Int, matches: Bool) async throws {
    let template = nestedProcedure(depth: depth, leaf: "1")
    let candidate = nestedProcedure(depth: depth, leaf: "1")
    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /substitute { true } bind def
        /Set << /deep [ \(template) bind /substitute load ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        \(candidate) bind /substitute load eq
        """
    )
    #expect(result.value == matches)
  }

  @Test
  func idiomVisibilityFollowsAllocationMode() async throws {
    let result: [IntegerValue] = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        true setglobal
        /GlobalSet << /one [ { 1 } bind { 10 } bind ] >> /IdiomSet defineresource pop
        false setglobal
        /LocalSet << /two [ { 2 } bind { 20 } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        true setglobal { 1 } bind exec
        { 2 } bind exec
        false setglobal { 1 } bind exec
        { 2 } bind exec
        """,
      count: 4
    )
    #expect(result.map(\.value) == [20, 10, 2, 10])
  }

  @Test
  func localSubstituteCannotReplaceGlobalCandidate() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /LocalSet << /one [ { 1 } bind { 42 } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        true setglobal { 1 } bind exec
        """
    )
    #expect(result.value == 1)
  }

  @Test
  func idiomResourceShadowingRestoreAndDuplicatePrecedence() async throws {
    let results: [IntegerValue] = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        true setglobal
        /Global << /entry [ { 1 } bind { 10 } bind ] >> /IdiomSet defineresource pop
        false setglobal
        save /saved exch def
        /Local << /entry [ { 1 } bind { 20 } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        { 1 } bind exec
        saved restore
        << /IdiomRecognition true >> setuserparams
        { 1 } bind exec
        """,
      count: 2
    )
    #expect(results.map(\.value) == [10, 20])

    let duplicate: IntegerValue = try await Interpreter.result(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        /First << /entry [ { 5 } bind { 50 } bind ] >> /IdiomSet defineresource pop
        /Second << /entry [ { 5 } bind { 55 } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        { 5 } bind exec
        """
    )
    #expect([50, 55].contains(duplicate.value))
  }

  @Test
  func idiomSetValidationUsesExactTypesAndAccessErrors() async throws {
    let malformed: NameValue = try await Interpreter.result(
      content:
        "{ /Bad << /entry 1 2 2 packedarray >> /IdiomSet defineresource } stopped pop $error /errorname get"
    )
    #expect(malformed.value == "typecheck")

    let unreadable: NameValue = try await Interpreter.result(
      content:
        """
        /pair [ { 1 } { 2 } ] noaccess def
        { /Bad << /entry /pair load >> /IdiomSet defineresource } stopped pop
        $error /errorname get
        """
    )
    #expect(unreadable.value == "invalidaccess")

    let context = Context()
    let invalid = try Object.dictionary(
      ["entry": .array([.integer(1)], access: .unlimited, vm: .local, kind: .literal)],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    await #expect(throws: Error.typeCheck) {
      try await IdiomSetValidation.instance.validateLoaded(key: "Bad", instance: invalid, context: context)
    }
  }

  @Test
  func standaloneExecutionPreloadsExternalIdiomsWithoutBindTimeLookup() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeIdiomResource("External", replacement: 42, to: root)

    let environment = InterpreterEnvironment()
    let beforePreload: IntegerValue = try await Interpreter.result(
      content:
        """
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        { 1 } bind exec
        """,
      environment: environment
    )
    #expect(beforePreload.value == 1)

    let afterPreload = try await Interpreter.results(
      content:
        """
        { 1 } bind exec
        /External /IdiomSet resourcestatus
        """,
      environment: environment
    )
    #expect(try afterPreload[3].value(as: IntegerValue.self).value == 42)
    #expect(try afterPreload[2].value(as: IntegerValue.self).value == 1)
    #expect(try afterPreload[0].value(as: BooleanValue.self).value)
  }

  @Test
  func preloadPreservesExistingDefinitionsAndAutomaticEntriesCanBeReclaimed() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeIdiomResource("Existing", replacement: 42, to: root)
    try writeIdiomResource("Automatic", input: 2, replacement: 43, to: root)

    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        true setglobal
        /Existing << /entry [ { 1 } bind { 99 } bind ] >> /IdiomSet defineresource pop
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        """,
      environment: environment
    )

    let result: BooleanValue = try await Interpreter.result(
      content:
        """
        { 1 } bind exec 99 eq
        /Existing /IdiomSet resourcestatus { pop 0 eq } { false } ifelse and
        /Automatic /IdiomSet resourcestatus { pop 1 eq } { false } ifelse and
        2 vmreclaim
        /Automatic /IdiomSet resourcestatus { pop 2 eq } { false } ifelse and
        """,
      environment: environment
    )
    #expect(result.value)
  }

  @Test
  func failedPreloadRollsBackTheWholePass() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeIdiomResource("AValid", replacement: 42, to: root)
    try writeResource(
      "ZBroken",
      body: "/Leaked << /entry [ { 2 } { 22 } ] >> /IdiomSet defineresource pop",
      to: root.appendingPathComponent("IdiomSet", isDirectory: true)
    )

    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams",
      environment: environment
    )
    await #expect(throws: Error.undefinedResource) {
      try await Interpreter.execute(content: "", environment: environment)
    }

    try environment.updateSystemParameters(
      from: DictionaryValue(
        value: [
          .literalName("GenericResourceDir"):
            .string("%null", access: .unlimited, vm: .local, kind: .literal),
        ],
        access: .unlimited,
        vm: .local
      )
    )
    let visible: BooleanValue = try await Interpreter.result(
      content:
        """
        /AValid /IdiomSet resourcestatus not
        /Leaked /IdiomSet resourcestatus not and
        """,
      environment: environment
    )
    #expect(visible.value)
  }

  @Test
  func configuredProvidersArePreloadedAndValidated() async throws {
    let environment = InterpreterEnvironment(resourceCategories: ["IdiomSet": ProvidedIdiomSets.valid])
    let result: [Object] = try await Interpreter.results(
      content: "{ 3 } bind exec /Provided /IdiomSet resourcestatus",
      environment: environment
    )
    #expect(try result[3].value(as: IntegerValue.self).value == 33)
    #expect(try result[2].value(as: IntegerValue.self).value == 1)

    let invalidEnvironment = InterpreterEnvironment(
      resourceCategories: ["IdiomSet": ProvidedIdiomSets.invalid]
    )
    await #expect(throws: Error.typeCheck) {
      try await Interpreter.execute(content: "", environment: invalidEnvironment)
    }

    let context = Context(environment: invalidEnvironment)
    do {
      try await context.prepareIdiomResources()
      Issue.record("Expected provider validation to fail")
    } catch let stop as ErrorStop {
      #expect(stop.error == .typeCheck)
    }
    try await context.pushAndRun(
      source: .dataFile(
        content: Data("$error /command get".utf8),
        access: .readOnly,
        vm: .local,
        kind: .executable
      )
    )
    let command = try await context.peekOperand().value(as: NameValue.self)
    #expect(command.value == "findresource")
  }

  @Test(arguments: [false, true])
  func jobTransitionsPreloadExternalIdioms(useExitServer: Bool) async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeIdiomResource("External", replacement: 42, to: root)

    let session = InterpreterSession()
    let transition = useExitServer
      ? "serverdict begin () exitserver"
      : "true () startjob pop"
    try await session.executeJob(
      content:
        """
        << /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams
        \(transition)
        { 1 } bind exec 42 ne { undefined } if
        """
    )
  }

  @Test
  func sessionJobStartPreloadsExternalIdioms() async throws {
    let root = try temporaryResourceDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeIdiomResource("External", replacement: 42, to: root)

    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content: "<< /GenericResourceDir (\(root.path)/) /GenericResourcePathSep (/) >> setsystemparams",
      environment: environment
    )
    let session = InterpreterSession(environment: environment)
    try await session.executeJob(content: "{ 1 } bind exec 42 ne { undefined } if")
  }

  @Test
  func sharedGlobalIdiomsAreSafeAcrossConcurrentContexts() async throws {
    let environment = InterpreterEnvironment()
    _ = try await Interpreter.execute(
      content:
        """
        << /IdiomRecognition false >> setuserparams
        true setglobal
        /Shared << /entry [ { 1 2 add } bind { 42 } bind ] >> /IdiomSet defineresource pop
        """,
      environment: environment
    )

    try await withThrowingTaskGroup(of: Int32.self) { group in
      for _ in 0..<20 {
        group.addTask {
          let value: IntegerValue = try await Interpreter.result(
            content: "{ 1 2 add } bind exec",
            environment: environment
          )
          return value.value
        }
      }
      for try await value in group {
        #expect(value == 42)
      }
    }
  }

  private func nestedProcedure(depth: Int, leaf: String) -> String {
    String(repeating: "{ ", count: depth) + leaf + String(repeating: " }", count: depth)
  }

  private func temporaryResourceDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeIdiomResource(_ name: String, input: Int = 1, replacement: Int, to root: URL) throws {
    let directory = root.appendingPathComponent("IdiomSet", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try writeResource(
      name,
      body:
        """
        << /IdiomRecognition false >> setuserparams
        /\(name) << /entry [ { \(input) } bind { \(replacement) } bind ] >> /IdiomSet defineresource pop
        << /IdiomRecognition true >> setuserparams
        """,
      to: directory
    )
  }

  private func writeResource(_ name: String, body: String, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(("%!PS\n" + body + "\n").utf8).write(to: directory.appendingPathComponent(name))
  }
}

private enum ProvidedIdiomSets: ResourceCategory {
  case valid
  case invalid

  var dictionary: ResourceCategoryDictionary {
    .init(category: "IdiomSet", instanceType: .dictionary, fileName: Operators.ResourceFileName.default)
  }

  var resourceExtension: (any Operators.ResourceCategoryExtension)? {
    IdiomSetValidation.instance
  }

  func statusOfResource(forKey key: Object) throws -> (isLoaded: Bool, size: Int)? {
    try canonicalResourceKey(key) == "Provided" ? (false, 32) : nil
  }

  func loadResource(forKey key: Object, in context: isolated Context) async throws -> Object {
    guard try canonicalResourceKey(key) == "Provided" else { throw Error.undefinedResource }
    if self == .invalid {
      return try .dictionary(
        ["entry": .integer(1)],
        access: .unlimited,
        vm: .global,
        kind: .literal
      )
    }

    let template = try Object.array([.integer(3)], access: .unlimited, vm: .global, kind: .executable)
    let substitute = try Object.array([.integer(33)], access: .unlimited, vm: .global, kind: .executable)
    let pair = try Object.array([template, substitute], access: .unlimited, vm: .global, kind: .literal)
    return try .dictionary(
      ["entry": pair],
      access: .unlimited,
      vm: .global,
      kind: .literal
    )
  }

  func enumerateResources(matching template: String) throws -> [Object] {
    [.literalName("Provided")]
  }
}
