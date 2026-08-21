import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package struct ConformanceProcessResult: Sendable, Hashable {
  package let terminationStatus: Int32
  package let standardOutput: Data
  package let standardError: Data
  package let timedOut: Bool
  package let outputLimitExceeded: Bool
}

package enum ConformanceProcessRunner {
  package static func run(
    executable: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    currentDirectory: URL? = nil,
    timeoutMilliseconds: Int,
    maximumOutputBytes: Int
  ) throws -> ConformanceProcessResult {
    let temporary = FileManager.default.temporaryDirectory
      .appending(path: "solid-ps-conformance-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let outputURL = temporary.appending(path: "stdout")
    let errorURL = temporary.appending(path: "stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let error = try FileHandle(forWritingTo: errorURL)
    defer {
      try? output.close()
      try? error.close()
    }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = currentDirectory
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = error
    try process.run()

    let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
    var timedOut = false
    var outputLimitExceeded = false
    while process.isRunning {
      if ContinuousClock.now >= deadline {
        timedOut = true
        process.terminate()
        break
      }
      let outputSize = try fileSize(outputURL)
      let errorSize = try fileSize(errorURL)
      if outputSize > maximumOutputBytes || errorSize > maximumOutputBytes {
        outputLimitExceeded = true
        process.terminate()
        break
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning {
      let grace = ContinuousClock.now + .milliseconds(250)
      while process.isRunning, ContinuousClock.now < grace { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()
    try output.synchronize()
    try error.synchronize()
    return ConformanceProcessResult(
      terminationStatus: process.terminationStatus,
      standardOutput: try boundedData(at: outputURL, maximumBytes: maximumOutputBytes),
      standardError: try boundedData(at: errorURL, maximumBytes: maximumOutputBytes),
      timedOut: timedOut,
      outputLimitExceeded: outputLimitExceeded
    )
  }

  private static func fileSize(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.intValue ?? 0
  }

  private static func boundedData(at url: URL, maximumBytes: Int) throws -> Data {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard data.count <= maximumBytes else { return Data(data.prefix(maximumBytes)) }
    return data
  }
}
