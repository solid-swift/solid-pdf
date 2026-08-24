import Foundation

package enum ConformanceCorpusDiscovery {
  package static func manifestSuites(in directory: URL) throws -> [ConformanceSuite] {
    try files(in: directory, extensions: Set(["json"])).map(ConformanceSuite.load(from:))
  }

  package static func postScriptSuite(in directory: URL, name: String = "external-discovery") throws
    -> ConformanceSuite
  {
    let root = directory.standardizedFileURL.resolvingSymlinksInPath()
    let programs = try files(in: root, extensions: Set(["ps", "eps", "epsi"]))
    let cases = programs.map { url in
      let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
      let relative = String(resolved.path.dropFirst(root.path.count + 1))
      let stem = relative.lowercased().map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
      let digest = ConformanceDigest.sha256(Data(relative.utf8)).prefix(16)
      return ConformanceCaseManifest(
        id: "external.\(digest).\(String(stem.prefix(48)))",
        title: relative,
        authority: [ConformanceAuthority(document: "external", section: "discovery")],
        tags: ["external", "discovery"],
        mode: .raw,
        source: relative,
        observations: [.raster],
        disposition: .discovery
      )
    }
    return ConformanceSuite(manifest: ConformanceSuiteManifest(name: name, cases: cases), root: root)
  }

  private static func files(in directory: URL, extensions: Set<String>) throws -> [URL] {
    let root = directory.standardizedFileURL.resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { throw ConformanceError.invalidPath(directory.path) }
    var result: [URL] = []
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      if values.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) { result.append(url) }
    }
    return result.sorted { $0.path < $1.path }
  }
}
