import ArgumentParser
import Foundation
import SolidPostScriptConformanceSupport

@main
struct SolidPSConformance: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "solid-ps-conformance",
    abstract: "Run independent PostScript conformance cases.",
    subcommands: [List.self, Run.self, Record.self, Discover.self, Worker.self, DiscoveryWorker.self]
  )
}

private struct Discover: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run an external PS/EPS directory as discovery-only cases.")

  @Argument(help: "External PS/EPS directory.") var directory: String
  @Option(name: .long, help: "Directory for discovery reports and artifacts.") var output = ".conformance-discovery"
  @Option(name: .long, help: "Pinned Ghostscript executable.") var reference: String
  @Option(name: .long, help: "Maximum cases to discover in deterministic path order.") var limit = 1_000
  @Option(name: .long, help: "Maximum concurrent workers.") var jobs: Int?

  mutating func run() async throws {
    do {
      try await execute()
    } catch let exitCode as ExitCode {
      throw exitCode
    } catch {
      try throwMapped(error)
    }
  }

  private func execute() async throws {
    guard limit > 0 else { throw ValidationError("limit must be positive") }
    let sourceRoot = URL(fileURLWithPath: directory).standardizedFileURL
    let suite = try ConformanceCorpusDiscovery.postScriptSuite(in: sourceRoot)
    let selected = Array(suite.manifest.cases.prefix(limit))
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let referenceURL = URL(fileURLWithPath: reference).standardizedFileURL
    guard FileManager.default.isExecutableFile(atPath: referenceURL.path) else { throw ExitCode(69) }
    let referenceVersion = try GhostscriptConformanceRunner.version(executable: referenceURL)
    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
    let artifactRoot = outputURL.appending(path: "artifacts-\(UUID().uuidString)", directoryHint: .isDirectory)
    let concurrency = min(max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1), 4)
    let results = await runDiscoveryWorkers(
      selected,
      sourceRoot: sourceRoot,
      executable: executable,
      reference: referenceURL,
      concurrency: concurrency,
      artifactRoot: artifactRoot
    )
    let report = ConformanceDiscoveryRunReport(
      suite: suite.manifest.name,
      referenceVersion: referenceVersion,
      results: results
    )
    try write(discoveryReport: report, to: outputURL)
    try ConformanceReferenceMetadata(executable: referenceURL.path, version: referenceVersion)
      .encodedJSON()
      .write(to: outputURL.appending(path: "reference-metadata.json"), options: .atomic)
    if report.exitStatus != 0 { throw ExitCode(report.exitStatus) }
  }
}

private struct List: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "List validated conformance cases.")

  @Argument(help: "Suite manifest path.") var suite: String

  mutating func run() throws {
    do {
      let loaded = try ConformanceSuite.load(from: URL(fileURLWithPath: suite))
      for testCase in loaded.manifest.cases.sorted(by: { $0.id < $1.id }) {
        print("\(testCase.id)\t\(testCase.disposition.rawValue)\t\(testCase.title)")
      }
    } catch {
      try throwMapped(error)
    }
  }
}

private struct Run: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run cases in isolated child workers.")

  @Argument(help: "Suite manifest path.") var suite: String
  @Option(name: .long, help: "Directory for JSON, JUnit, and failure artifacts.") var output = ".conformance-results"
  @Option(name: .long, help: "Maximum concurrent workers.") var jobs: Int?
  @Option(name: .long, help: "Pinned Ghostscript executable used for differential validation.") var reference: String?
  @Option(name: .long, parsing: .upToNextOption, help: "Case tags to include.") var tags: [String] = []

  mutating func run() async throws {
    do {
      try await execute()
    } catch let exitCode as ExitCode {
      throw exitCode
    } catch {
      try throwMapped(error)
    }
  }

  private func execute() async throws {
    let suiteURL = URL(fileURLWithPath: suite).standardizedFileURL
    let loaded = try ConformanceSuite.load(from: suiteURL)
    let selected = loaded.manifest.cases.filter { testCase in
      tags.isEmpty || !Set(tags).isDisjoint(with: testCase.tags)
    }
    let concurrency = min(max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1), 4)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
    let artifactRoot = outputURL.appending(path: "artifacts-\(UUID().uuidString)", directoryHint: .isDirectory)
    let referenceURL = reference.map { URL(fileURLWithPath: $0).standardizedFileURL }
    if let referenceURL, !FileManager.default.isExecutableFile(atPath: referenceURL.path) { throw ExitCode(69) }
    let referenceVersion = try referenceURL.map { try GhostscriptConformanceRunner.version(executable: $0) }
    let results = await runWorkers(
      selected,
      suiteURL: suiteURL,
      executable: executable,
      reference: referenceURL,
      concurrency: concurrency,
      artifactRoot: artifactRoot
    )
    let report = ConformanceRunReport(
      suite: loaded.manifest.name,
      referenceVersion: referenceVersion,
      results: results
    )
    try write(report: report, to: outputURL)
    if let referenceURL, let referenceVersion {
      try ConformanceReferenceMetadata(executable: referenceURL.path, version: referenceVersion)
        .encodedJSON()
        .write(to: outputURL.appending(path: "reference-metadata.json"), options: .atomic)
    }
    if report.exitStatus != 0 { throw ExitCode(report.exitStatus) }
  }
}

private struct Record: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Stage candidate Solid expectations without replacing goldens.")

  @Argument(help: "Suite manifest path.") var suite: String
  @Option(name: .long, help: "New, empty staging directory.") var output: String

  mutating func run() async throws {
    do {
      try await execute()
    } catch let exitCode as ExitCode {
      throw exitCode
    } catch {
      try throwMapped(error)
    }
  }

  private func execute() async throws {
    let destination = URL(fileURLWithPath: output).standardizedFileURL
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ValidationError("record output already exists")
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let loaded = try ConformanceSuite.load(from: URL(fileURLWithPath: suite))
    for testCase in loaded.manifest.cases.sorted(by: { $0.id < $1.id }) {
      let result = try await SolidConformanceRunner.run(testCase, in: loaded)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let transcriptPath: String?
      if let transcript = result.transcript {
        let path = "\(testCase.id).transcript"
        transcriptPath = path
        try transcript.write(to: destination.appending(path: path), options: .withoutOverwriting)
      } else {
        transcriptPath = nil
      }
      let candidate = ConformanceExpectedResult(
        transcript: transcriptPath,
        recordingDigest: result.recordingDigest,
        rasterDigests: result.rasterDigests
      )
      try (encoder.encode(candidate) + Data([0x0A])).write(
        to: destination.appending(path: "\(testCase.id).candidate.json"),
        options: .withoutOverwriting
      )
    }
  }
}

private func throwMapped(_ error: any Error) throws -> Never {
  FileHandle.standardError.write(Data("solid-ps-conformance: \(error)\n".utf8))
  if error is ValidationError { throw ExitCode(64) }
  if let conformanceError = error as? ConformanceError {
    switch conformanceError {
    case .invalidManifest, .invalidPath:
      throw ExitCode(64)
    case .missingReference:
      throw ExitCode(69)
    default:
      throw ExitCode(70)
    }
  }
  throw ExitCode(70)
}

private struct Worker: AsyncParsableCommand {
  static let configuration = CommandConfiguration(commandName: "worker", shouldDisplay: false)

  @Argument var suite: String
  @Argument var caseID: String
  @Argument var artifacts: String?

  mutating func run() async throws {
    let loaded = try ConformanceSuite.load(from: URL(fileURLWithPath: suite))
    guard let testCase = loaded.manifest.cases.first(where: { $0.id == caseID }) else {
      throw ValidationError("unknown case \(caseID)")
    }
    let result = try await SolidConformanceRunner.runWithRasters(testCase, in: loaded)
    if let artifacts {
      let directory = URL(fileURLWithPath: artifacts).standardizedFileURL
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (index, raster) in result.rasterPages.enumerated() {
        try PortableAnyMap.encode(raster).write(
          to: directory.appending(path: String(format: "solid-%04d.ppm", index + 1)),
          options: .atomic
        )
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(result.observation) + Data([0x0A]))
  }
}

private struct DiscoveryWorker: AsyncParsableCommand {
  static let configuration = CommandConfiguration(commandName: "discovery-worker", shouldDisplay: false)

  @Argument var directory: String
  @Argument var caseID: String
  @Argument var artifacts: String

  mutating func run() async throws {
    let suite = try ConformanceCorpusDiscovery.postScriptSuite(in: URL(fileURLWithPath: directory))
    guard let testCase = suite.manifest.cases.first(where: { $0.id == caseID }) else {
      throw ValidationError("unknown discovery case \(caseID)")
    }
    let result = try await SolidConformanceRunner.runWithRasters(testCase, in: suite)
    let directory = URL(fileURLWithPath: artifacts).standardizedFileURL
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (index, raster) in result.rasterPages.enumerated() {
      try PortableAnyMap.encode(raster).write(
        to: directory.appending(path: String(format: "solid-%04d.ppm", index + 1)),
        options: .atomic
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(result.observation) + Data([0x0A]))
  }
}

private func runWorkers(
  _ cases: [ConformanceCaseManifest],
  suiteURL: URL,
  executable: URL,
  reference: URL?,
  concurrency: Int,
  artifactRoot: URL
) async -> [ConformanceCaseResult] {
  await withTaskGroup(of: ConformanceCaseResult.self, returning: [ConformanceCaseResult].self) { group in
    var iterator = cases.makeIterator()
    for _ in 0..<min(concurrency, cases.count) {
      if let testCase = iterator.next() {
        addWorker(
          testCase,
          suiteURL: suiteURL,
          executable: executable,
          reference: reference,
          artifactRoot: artifactRoot,
          to: &group
        )
      }
    }
    var results: [ConformanceCaseResult] = []
    while let result = await group.next() {
      results.append(result)
      if let testCase = iterator.next() {
        addWorker(
          testCase,
          suiteURL: suiteURL,
          executable: executable,
          reference: reference,
          artifactRoot: artifactRoot,
          to: &group
        )
      }
    }
    return results
  }
}

private func addWorker(
  _ testCase: ConformanceCaseManifest,
  suiteURL: URL,
  executable: URL,
  reference: URL?,
  artifactRoot: URL,
  to group: inout TaskGroup<ConformanceCaseResult>
) {
  group.addTask {
    let start = ContinuousClock.now
    let artifactDirectory = artifactRoot.appending(path: testCase.id, directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
      let process = try ConformanceProcessRunner.run(
        executable: executable,
        arguments: ["worker", suiteURL.path, testCase.id, artifactDirectory.path],
        timeoutMilliseconds: testCase.limits.timeoutMilliseconds,
        maximumOutputBytes: testCase.limits.maximumTranscriptBytes
      )
      let elapsed = start.duration(to: .now)
      let milliseconds = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
      guard !process.timedOut, !process.outputLimitExceeded, process.terminationStatus == 0 else {
        return ConformanceCaseResult(
          id: testCase.id,
          status: .harnessFailure,
          durationMilliseconds: milliseconds,
          diagnostic: process.timedOut ? "worker timed out" : "worker failed: \(String(decoding: process.standardError, as: UTF8.self))"
        )
      }
      let observation = try JSONDecoder().decode(ConformanceObservationResult.self, from: process.standardOutput)
      let suite = try ConformanceSuite.load(from: suiteURL)
      let ghostscript = try reference.map {
        try GhostscriptConformanceRunner.run(testCase, in: suite, executable: $0)
      }
      let rasterDifferences = try compareRasters(
        testCase,
        solidDirectory: artifactDirectory,
        reference: ghostscript?.rasterPages
      )
      let result = try ConformanceAdjudicator.evaluate(
        testCase,
        suite: suite,
        solid: observation,
        reference: ghostscript?.observation,
        referenceVersion: ghostscript?.version,
        durationMilliseconds: milliseconds,
        additionalDifferences: rasterDifferences
      )
      if result.status == .passed { try? FileManager.default.removeItem(at: artifactDirectory) }
      return result
    } catch {
      return ConformanceCaseResult(
        id: testCase.id,
        status: .harnessFailure,
        durationMilliseconds: 0,
        diagnostic: String(describing: error)
      )
    }
  }
}

private func runDiscoveryWorkers(
  _ cases: [ConformanceCaseManifest],
  sourceRoot: URL,
  executable: URL,
  reference: URL,
  concurrency: Int,
  artifactRoot: URL
) async -> [ConformanceDiscoveryCaseResult] {
  await withTaskGroup(
    of: ConformanceDiscoveryCaseResult.self,
    returning: [ConformanceDiscoveryCaseResult].self
  ) { group in
    var iterator = cases.makeIterator()
    for _ in 0..<min(concurrency, cases.count) {
      if let testCase = iterator.next() {
        addDiscoveryWorker(
          testCase,
          sourceRoot: sourceRoot,
          executable: executable,
          reference: reference,
          artifactRoot: artifactRoot,
          to: &group
        )
      }
    }
    var results: [ConformanceDiscoveryCaseResult] = []
    while let result = await group.next() {
      results.append(result)
      if let testCase = iterator.next() {
        addDiscoveryWorker(
          testCase,
          sourceRoot: sourceRoot,
          executable: executable,
          reference: reference,
          artifactRoot: artifactRoot,
          to: &group
        )
      }
    }
    return results
  }
}

private func addDiscoveryWorker(
  _ testCase: ConformanceCaseManifest,
  sourceRoot: URL,
  executable: URL,
  reference: URL,
  artifactRoot: URL,
  to group: inout TaskGroup<ConformanceDiscoveryCaseResult>
) {
  group.addTask {
    let start = ContinuousClock.now
    let artifactDirectory = artifactRoot.appending(path: testCase.id, directoryHint: .isDirectory)
    let sourceDigest: String
    do {
      let source = try Data(contentsOf: sourceRoot.appending(path: testCase.source), options: [.mappedIfSafe])
      sourceDigest = ConformanceDigest.sha256(source)
    } catch {
      return ConformanceDiscoveryCaseResult(
        id: testCase.id,
        source: testCase.source,
        sourceDigest: "",
        outcome: .harnessFailure,
        durationMilliseconds: 0,
        diagnostic: "source digest failed"
      )
    }
    do {
      try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
      let process = try ConformanceProcessRunner.run(
        executable: executable,
        arguments: ["discovery-worker", sourceRoot.path, testCase.id, artifactDirectory.path],
        timeoutMilliseconds: testCase.limits.timeoutMilliseconds,
        maximumOutputBytes: testCase.limits.maximumTranscriptBytes
      )
      let elapsed = start.duration(to: .now)
      let milliseconds = Int(elapsed.components.seconds * 1_000)
        + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
      if process.timedOut || process.outputLimitExceeded {
        return ConformanceDiscoveryCaseResult(
          id: testCase.id,
          source: testCase.source,
          sourceDigest: sourceDigest,
          outcome: .executionLimit,
          durationMilliseconds: milliseconds,
          diagnostic: process.timedOut ? "Solid execution timed out" : "Solid execution exceeded output limits",
          artifactPaths: artifactPaths(in: artifactDirectory, relativeTo: artifactRoot)
        )
      }
      guard process.terminationStatus == 0 else {
        return ConformanceDiscoveryCaseResult(
          id: testCase.id,
          source: testCase.source,
          sourceDigest: sourceDigest,
          outcome: .compatibilityDifference,
          durationMilliseconds: milliseconds,
          diagnostic: ConformanceDiscoveryDiagnostic.normalize(
            process.standardError,
            prefix: "Solid execution failed"
          ),
          artifactPaths: artifactPaths(in: artifactDirectory, relativeTo: artifactRoot)
        )
      }
      let solid = try JSONDecoder().decode(ConformanceObservationResult.self, from: process.standardOutput)
      let suite = try ConformanceCorpusDiscovery.postScriptSuite(in: sourceRoot)
      let ghostscript: GhostscriptConformanceResult
      do {
        ghostscript = try GhostscriptConformanceRunner.run(testCase, in: suite, executable: reference)
      } catch {
        return ConformanceDiscoveryCaseResult(
          id: testCase.id,
          source: testCase.source,
          sourceDigest: sourceDigest,
          outcome: .compatibilityDifference,
          durationMilliseconds: milliseconds,
          solid: solid,
          diagnostic: ConformanceDiscoveryDiagnostic.normalize(
            String(describing: error),
            prefix: "reference execution failed"
          ),
          artifactPaths: artifactPaths(in: artifactDirectory, relativeTo: artifactRoot)
        )
      }
      let rasterDifferences = try compareRasters(
        testCase,
        solidDirectory: artifactDirectory,
        reference: ghostscript.rasterPages
      )
      let result = try ConformanceAdjudicator.evaluate(
        testCase,
        suite: suite,
        solid: solid,
        reference: ghostscript.observation,
        referenceVersion: ghostscript.version,
        durationMilliseconds: milliseconds,
        additionalDifferences: rasterDifferences
      )
      if result.status == .passed { try? FileManager.default.removeItem(at: artifactDirectory) }
      return ConformanceDiscoveryCaseResult(
        id: testCase.id,
        source: testCase.source,
        sourceDigest: sourceDigest,
        outcome: result.status == .passed ? .equivalent : .compatibilityDifference,
        durationMilliseconds: milliseconds,
        solid: solid,
        reference: ghostscript.observation,
        differences: result.differences,
        diagnostic: result.diagnostic,
        artifactPaths: artifactPaths(in: artifactDirectory, relativeTo: artifactRoot)
      )
    } catch {
      return ConformanceDiscoveryCaseResult(
        id: testCase.id,
        source: testCase.source,
        sourceDigest: sourceDigest,
        outcome: .harnessFailure,
        durationMilliseconds: 0,
        diagnostic: ConformanceDiscoveryDiagnostic.normalize(
          String(describing: error),
          prefix: "discovery harness failed"
        ),
        artifactPaths: artifactPaths(in: artifactDirectory, relativeTo: artifactRoot)
      )
    }
  }
}

private func artifactPaths(in directory: URL, relativeTo root: URL) -> [String] {
  guard let values = try? FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: [.isRegularFileKey]
  ) else { return [] }
  return values.compactMap { value in
    guard (try? value.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
    return "\(root.lastPathComponent)/\(directory.lastPathComponent)/\(value.lastPathComponent)"
  }.sorted()
}

private func compareRasters(
  _ testCase: ConformanceCaseManifest,
  solidDirectory: URL,
  reference: [PortableRaster]?
) throws -> [String] {
  guard testCase.observations.contains(.raster), let reference,
    testCase.disposition == .equivalent || testCase.disposition == .discovery
  else { return [] }
  let solidURLs = try FileManager.default.contentsOfDirectory(at: solidDirectory, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("solid-") && $0.pathExtension == "ppm" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  let solid = try solidURLs.map {
    try PortableAnyMap.decode(Data(contentsOf: $0), maximumPixels: testCase.limits.maximumRasterPixels)
  }
  guard solid.count == reference.count else {
    return ["Solid raster page count \(solid.count) differs from reference count \(reference.count)"]
  }
  var differences: [String] = []
  var temporaryBytes = solidURLs.reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) }
  for index in solid.indices {
    do {
      let comparison = try ConformanceRasterComparator.compare(solid[index], reference[index], tolerance: testCase.rasterTolerance)
      guard !comparison.isEquivalent else { continue }
      differences.append(
        "raster page \(index + 1) differs: max=\(comparison.maximumChannelDifference), rmse=\(comparison.normalizedRMSE)"
      )
      let referenceData = try PortableAnyMap.encode(reference[index])
      let differenceData = try PortableAnyMap.encode(
        ConformanceRasterComparator.differenceImage(solid[index], reference[index])
      )
      temporaryBytes += referenceData.count + differenceData.count
      guard temporaryBytes <= testCase.limits.maximumTemporaryBytes else {
        throw ConformanceError.rasterLimitExceeded
      }
      try referenceData.write(
        to: solidDirectory.appending(path: String(format: "reference-%04d.ppm", index + 1)),
        options: .atomic
      )
      try differenceData.write(
        to: solidDirectory.appending(path: String(format: "difference-%04d.ppm", index + 1)),
        options: .atomic
      )
    } catch {
      differences.append("raster page \(index + 1) is structurally incomparable: \(error)")
    }
  }
  return differences
}

private func write(report: ConformanceRunReport, to directory: URL) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try report.encodedJSON().write(to: directory.appending(path: "report.json"), options: .atomic)
  try report.encodedJUnit().write(to: directory.appending(path: "report.junit.xml"), options: .atomic)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  for result in report.results where result.status != .passed {
    try (encoder.encode(result) + Data([0x0A])).write(
      to: directory.appending(path: "\(result.id).failure.json"),
      options: .atomic
    )
    if let transcript = result.solid?.transcript {
      try transcript.write(to: directory.appending(path: "\(result.id).solid.transcript"), options: .atomic)
    }
    if let transcript = result.reference?.transcript {
      try transcript.write(to: directory.appending(path: "\(result.id).reference.transcript"), options: .atomic)
    }
    if let transcript = result.solid?.transcript,
      let normalized = try? ConformanceTranscript.parse(transcript, maximumBytes: max(transcript.count, 1))
    {
      try (encoder.encode(normalized) + Data([0x0A])).write(
        to: directory.appending(path: "\(result.id).solid.normalized.json"),
        options: .atomic
      )
    }
    if let transcript = result.reference?.transcript,
      let normalized = try? ConformanceTranscript.parse(transcript, maximumBytes: max(transcript.count, 1))
    {
      try (encoder.encode(normalized) + Data([0x0A])).write(
        to: directory.appending(path: "\(result.id).reference.normalized.json"),
        options: .atomic
      )
    }
    if let solid = result.solid {
      let candidate = ConformanceExpectedResult(
        transcript: solid.transcript == nil ? nil : "Expected/\(result.id).transcript",
        recordingDigest: solid.recordingDigest,
        rasterDigests: solid.rasterDigests
      )
      try (encoder.encode(candidate) + Data([0x0A])).write(
        to: directory.appending(path: "\(result.id).candidate.json"),
        options: .atomic
      )
    }
  }
}

private func write(discoveryReport report: ConformanceDiscoveryRunReport, to directory: URL) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try report.encodedJSON().write(to: directory.appending(path: "report.json"), options: .atomic)
  try report.encodedJUnit().write(to: directory.appending(path: "report.junit.xml"), options: .atomic)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  for result in report.results where result.outcome != .equivalent {
    try (encoder.encode(result) + Data([0x0A])).write(
      to: directory.appending(path: "\(result.id).failure.json"),
      options: .atomic
    )
    if let transcript = result.solid?.transcript {
      try transcript.write(to: directory.appending(path: "\(result.id).solid.transcript"), options: .atomic)
    }
    if let transcript = result.reference?.transcript {
      try transcript.write(
        to: directory.appending(path: "\(result.id).reference.transcript"),
        options: .atomic
      )
    }
  }
}
