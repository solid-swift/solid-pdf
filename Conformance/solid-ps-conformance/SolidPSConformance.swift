import ArgumentParser
import Foundation
import SolidPostScriptConformanceSupport

@main
struct SolidPSConformance: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "solid-ps-conformance",
    abstract: "Run independent PostScript conformance cases.",
    subcommands: [List.self, Run.self, Record.self, Worker.self]
  )
}

private struct List: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "List validated conformance cases.")

  @Argument(help: "Suite manifest path.") var suite: String

  mutating func run() throws {
    let loaded = try ConformanceSuite.load(from: URL(fileURLWithPath: suite))
    for testCase in loaded.manifest.cases.sorted(by: { $0.id < $1.id }) {
      print("\(testCase.id)\t\(testCase.disposition.rawValue)\t\(testCase.title)")
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
    let suiteURL = URL(fileURLWithPath: suite).standardizedFileURL
    let loaded = try ConformanceSuite.load(from: suiteURL)
    let selected = loaded.manifest.cases.filter { testCase in
      tags.isEmpty || !Set(tags).isDisjoint(with: testCase.tags)
    }
    let concurrency = min(max(jobs ?? ProcessInfo.processInfo.activeProcessorCount, 1), 4)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let referenceURL = reference.map { URL(fileURLWithPath: $0).standardizedFileURL }
    if let referenceURL, !FileManager.default.isExecutableFile(atPath: referenceURL.path) { throw ExitCode(69) }
    let referenceVersion = try referenceURL.map { try GhostscriptConformanceRunner.version(executable: $0) }
    let results = await runWorkers(
      selected,
      suiteURL: suiteURL,
      executable: executable,
      reference: referenceURL,
      concurrency: concurrency
    )
    let report = ConformanceRunReport(
      suite: loaded.manifest.name,
      referenceVersion: referenceVersion,
      results: results
    )
    try write(report: report, to: URL(fileURLWithPath: output))
    if report.exitStatus != 0 { throw ExitCode(report.exitStatus) }
  }
}

private struct Record: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Stage candidate Solid expectations without replacing goldens.")

  @Argument(help: "Suite manifest path.") var suite: String
  @Option(name: .long, help: "New, empty staging directory.") var output: String

  mutating func run() async throws {
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
      try (encoder.encode(result) + Data([0x0A])).write(
        to: destination.appending(path: "\(testCase.id).candidate.json"),
        options: .withoutOverwriting
      )
    }
  }
}

private struct Worker: AsyncParsableCommand {
  static let configuration = CommandConfiguration(commandName: "worker", shouldDisplay: false)

  @Argument var suite: String
  @Argument var caseID: String

  mutating func run() async throws {
    let loaded = try ConformanceSuite.load(from: URL(fileURLWithPath: suite))
    guard let testCase = loaded.manifest.cases.first(where: { $0.id == caseID }) else {
      throw ValidationError("unknown case \(caseID)")
    }
    let result = try await SolidConformanceRunner.run(testCase, in: loaded)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(result) + Data([0x0A]))
  }
}

private func runWorkers(
  _ cases: [ConformanceCaseManifest],
  suiteURL: URL,
  executable: URL,
  reference: URL?,
  concurrency: Int
) async -> [ConformanceCaseResult] {
  await withTaskGroup(of: ConformanceCaseResult.self, returning: [ConformanceCaseResult].self) { group in
    var iterator = cases.makeIterator()
    for _ in 0..<min(concurrency, cases.count) {
      if let testCase = iterator.next() {
        addWorker(testCase, suiteURL: suiteURL, executable: executable, reference: reference, to: &group)
      }
    }
    var results: [ConformanceCaseResult] = []
    while let result = await group.next() {
      results.append(result)
      if let testCase = iterator.next() {
        addWorker(testCase, suiteURL: suiteURL, executable: executable, reference: reference, to: &group)
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
  to group: inout TaskGroup<ConformanceCaseResult>
) {
  group.addTask {
    let start = ContinuousClock.now
    do {
      let process = try ConformanceProcessRunner.run(
        executable: executable,
        arguments: ["worker", suiteURL.path, testCase.id],
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
      return try ConformanceAdjudicator.evaluate(
        testCase,
        suite: suite,
        solid: observation,
        reference: ghostscript?.observation,
        referenceVersion: ghostscript?.version,
        durationMilliseconds: milliseconds
      )
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
  }
}
