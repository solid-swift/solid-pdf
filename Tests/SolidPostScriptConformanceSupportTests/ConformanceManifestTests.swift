import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceManifestTests {
  @Test func loadsAConfinedManifest() throws {
    let temporary = try TemporaryDirectory()
    try Data("(result) 42 emit\n".utf8).write(to: temporary.url.appending(path: "case.ps"))
    try manifest(source: "case.ps").write(to: temporary.url.appending(path: "suite.json"))

    let suite = try ConformanceSuite.load(from: temporary.url.appending(path: "suite.json"))

    #expect(suite.manifest.cases.map(\.id) == ["objects.integer"])
    #expect(try suite.sourceURL(for: suite.manifest.cases[0]).lastPathComponent == "case.ps")
  }

  @Test func rejectsDuplicateIdentifiers() throws {
    let temporary = try TemporaryDirectory()
    try Data().write(to: temporary.url.appending(path: "case.ps"))
    let testCase = caseJSON(source: "case.ps")
    let data = Data("""
      {"schemaVersion":1,"name":"duplicates","cases":[\(testCase),\(testCase)]}
      """.utf8)
    try data.write(to: temporary.url.appending(path: "suite.json"))

    #expect(throws: ConformanceError.self) {
      try ConformanceSuite.load(from: temporary.url.appending(path: "suite.json"))
    }
  }

  @Test func rejectsEscapingFixturePaths() throws {
    let temporary = try TemporaryDirectory()
    try manifest(source: "../outside.ps").write(to: temporary.url.appending(path: "suite.json"))

    #expect(throws: ConformanceError.self) {
      try ConformanceSuite.load(from: temporary.url.appending(path: "suite.json"))
    }
  }

  @Test func acceptedDifferencesRequirePinnedResults() throws {
    let temporary = try TemporaryDirectory()
    try Data().write(to: temporary.url.appending(path: "case.ps"))
    let data = Data("""
      {"schemaVersion":1,"name":"accepted","cases":[{
        "id":"objects.integer","title":"Integer","authority":[{"document":"PLRM3","section":"3.2"}],
        "source":"case.ps","disposition":"acceptedDifference"
      }]}
      """.utf8)
    try data.write(to: temporary.url.appending(path: "suite.json"))

    #expect(throws: ConformanceError.self) {
      try ConformanceSuite.load(from: temporary.url.appending(path: "suite.json"))
    }
  }

  private func manifest(source: String) -> Data {
    Data("""
      {"schemaVersion":1,"name":"unit","cases":[\(caseJSON(source: source))]}
      """.utf8)
  }

  private func caseJSON(source: String) -> String {
    """
    {"id":"objects.integer","title":"Integer","authority":[{"document":"PLRM3","section":"3.2"}],"source":"\(source)","disposition":"discovery"}
    """
  }
}

private final class TemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "conformance-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }
}
