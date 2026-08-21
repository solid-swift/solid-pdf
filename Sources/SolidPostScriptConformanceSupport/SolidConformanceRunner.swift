import Foundation
import SolidIO
import SolidPostScript
import SolidPostScriptDocument
import SolidPostScriptRaster
import SolidRaster

package enum SolidConformanceRunner {
  package static func run(_ testCase: ConformanceCaseManifest, in suite: ConformanceSuite) async throws
    -> ConformanceObservationResult
  {
    try await runWithRasters(testCase, in: suite).observation
  }

  package static func runWithRasters(_ testCase: ConformanceCaseManifest, in suite: ConformanceSuite) async throws
    -> (observation: ConformanceObservationResult, rasterPages: [PortableRaster])
  {
    let sourceURL = try suite.sourceURL(for: testCase)
    let source = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
    guard source.count <= testCase.limits.maximumInputBytes else { throw ConformanceError.inputLimitExceeded }
    let program = try ConformanceProbe.instrument(source, mode: testCase.mode)
    let standardOutput = DataSink()
    let standardError = DataSink()
    let host = InterpreterHostConfiguration(
      standardInput: DataSource(data: Data()),
      standardOutput: standardOutput,
      standardError: standardError,
      interactiveExecutiveEnabled: false
    )
    let environment = InterpreterEnvironment(
      hostConfiguration: host,
      fileDevices: FileDevices(devices: [try RootedReadOnlyFileDevice(roots: [suite.root])])
    )

    var recordingDigest: String?
    var rasterDigests: [String] = []
    var rasterPages: [PortableRaster] = []
    let file = { DataFile(data: program, mode: .read) }
    if testCase.observations.contains(.recording) {
      let rendered = try await Interpreter.render(file: file(), to: RecordingGraphicsTarget(), environment: environment)
      recordingDigest = digest(recording: rendered.output)
    } else if testCase.observations.contains(.raster) {
      let rendered = try await Interpreter.render(file: file(), to: RasterImageTarget(), environment: environment)
      rasterPages = try rendered.output.map { try portableRaster(image: $0, limit: testCase.limits.maximumRasterPixels) }
      rasterDigests = rasterPages.map(\.digest)
    } else {
      _ = try await Interpreter.execute(file: file(), environment: environment)
    }
    let transcript: Data?
    if testCase.observations.contains(.transcript) {
      guard standardOutput.data.count <= testCase.limits.maximumTranscriptBytes else {
        throw ConformanceError.transcriptLimitExceeded
      }
      transcript = standardOutput.data
    } else {
      transcript = nil
    }
    return (
      ConformanceObservationResult(
        transcript: transcript,
        recordingDigest: recordingDigest,
        rasterDigests: rasterDigests
      ),
      rasterPages
    )
  }

  private static func digest(recording: GraphicsRecording) -> String {
    ConformanceRecordingCanonicalizer.digest(recording)
  }

  private static func portableRaster(image: RasterImage, limit: Int) throws -> PortableRaster {
    let pixels = image.width.multipliedReportingOverflow(by: image.height)
    guard !pixels.overflow, pixels.partialValue <= limit else { throw ConformanceError.rasterLimitExceeded }
    var rgb = Data()
    rgb.reserveCapacity(pixels.partialValue * 3)
    for y in 0..<image.height {
      let row = y * image.bytesPerRow
      for x in 0..<image.width {
        let pixel = row + x * 4
        rgb.append(image.data[pixel])
        rgb.append(image.data[pixel + 1])
        rgb.append(image.data[pixel + 2])
      }
    }
    return try PortableRaster(width: image.width, height: image.height, channels: 3, pixels: rgb)
  }
}
