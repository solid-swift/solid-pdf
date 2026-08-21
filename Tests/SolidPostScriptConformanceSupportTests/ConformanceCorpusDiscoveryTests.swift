import Foundation
import SolidPostScriptConformanceSupport
import Testing

@Suite struct ConformanceCorpusDiscoveryTests {
  @Test func discoversPostScriptWithoutCopyingIt() throws {
    let temporary = FileManager.default.temporaryDirectory
      .appending(path: "conformance-corpus-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Data("showpage\n".utf8).write(to: temporary.appending(path: "Example.PS"))
    try Data("ignored".utf8).write(to: temporary.appending(path: "README.txt"))

    let suite = try ConformanceCorpusDiscovery.postScriptSuite(in: temporary)

    #expect(suite.manifest.cases.count == 1)
    #expect(suite.manifest.cases[0].disposition == .discovery)
    #expect(try suite.sourceURL(for: suite.manifest.cases[0]) == temporary.appending(path: "Example.PS"))
  }
}
