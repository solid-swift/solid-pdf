import Foundation

package struct GhostscriptConformanceResult: Sendable, Hashable {
  package let version: String
  package let observation: ConformanceObservationResult
  package let rasterPages: [PortableRaster]
  package let command: [String]
}

package enum GhostscriptConformanceRunner {
  package static func version(executable: URL) throws -> String {
    let process = try ConformanceProcessRunner.run(
      executable: executable,
      arguments: ["--version"],
      timeoutMilliseconds: 5_000,
      maximumOutputBytes: 4_096
    )
    guard process.terminationStatus == 0 else { throw ConformanceError.missingReference }
    return String(decoding: process.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  package static func run(
    _ testCase: ConformanceCaseManifest,
    in suite: ConformanceSuite,
    executable: URL
  ) throws -> GhostscriptConformanceResult {
    let source = try Data(contentsOf: suite.sourceURL(for: testCase), options: [.mappedIfSafe])
    guard source.count <= testCase.limits.maximumInputBytes else { throw ConformanceError.inputLimitExceeded }
    let program = try ConformanceProbe.instrument(source, mode: testCase.mode)
    let temporary = FileManager.default.temporaryDirectory
      .appending(path: "solid-ps-gs-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let programURL = temporary.appending(path: "case.ps")
    try program.write(to: programURL, options: .atomic)

    var arguments = ["-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-dNOFONTMAP"]
    let wantsRaster = testCase.observations.contains(.raster)
    if wantsRaster {
      arguments += ["-sDEVICE=ppmraw", "-r72", "-sOutputFile=page-%04d.ppm"]
    } else {
      arguments.append("-dNODISPLAY")
    }
    arguments += ["--permit-file-read=\(suite.root.path)/*", programURL.path]
    let process = try ConformanceProcessRunner.run(
      executable: executable,
      arguments: arguments,
      currentDirectory: temporary,
      timeoutMilliseconds: testCase.limits.timeoutMilliseconds,
      maximumOutputBytes: testCase.limits.maximumTranscriptBytes
    )
    guard !process.timedOut, !process.outputLimitExceeded, process.terminationStatus == 0 else {
      throw ConformanceError.processFailed(String(decoding: process.standardError, as: UTF8.self))
    }
    let rasterURLs = try FileManager.default.contentsOfDirectory(
      at: temporary,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ppm" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let rasters = try rasterURLs.map {
      try PortableAnyMap.decode(Data(contentsOf: $0), maximumPixels: testCase.limits.maximumRasterPixels)
    }
    return GhostscriptConformanceResult(
      version: try version(executable: executable),
      observation: ConformanceObservationResult(
        transcript: testCase.observations.contains(.transcript) ? process.standardOutput : nil,
        rasterDigests: rasters.map(\.digest)
      ),
      rasterPages: rasters,
      command: [executable.path] + arguments
    )
  }
}
