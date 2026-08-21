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
    let file = { DataFile(data: program, mode: .read) }
    if testCase.observations.contains(.recording) {
      let rendered = try await Interpreter.render(file: file(), to: RecordingGraphicsTarget(), environment: environment)
      recordingDigest = digest(recording: rendered.output)
    } else if testCase.observations.contains(.raster) {
      let rendered = try await Interpreter.render(file: file(), to: RasterImageTarget(), environment: environment)
      rasterDigests = try rendered.output.map { try digest(image: $0, limit: testCase.limits.maximumRasterPixels) }
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
    return ConformanceObservationResult(
      transcript: transcript,
      recordingDigest: recordingDigest,
      rasterDigests: rasterDigests
    )
  }

  private static func digest(recording: GraphicsRecording) -> String {
    var value = Data("recording-v1\n".utf8)
    for (pageIndex, page) in recording.pages.enumerated() {
      value.append(Data(
        "page \(pageIndex) \(page.deviceDescriptor.mediaBounds.width.bitPattern) \(page.deviceDescriptor.mediaBounds.height.bitPattern)\n".utf8
      ))
      for effect in page.effects { value.append(Data("\(effectSummary(effect))\n".utf8)) }
    }
    return ConformanceDigest.sha256(value)
  }

  private static func effectSummary(_ effect: GraphicsEffect) -> String {
    switch effect {
    case .fill(let path, let rule, _): "fill \(rule) \(path.elements.count)"
    case .stroke(let path, _): "stroke \(path.elements.count)"
    case .userPathFill(let path, let rule, _): "upfill \(rule) \(path.elements.count)"
    case .userPathStroke(let outline, _): "upstroke \(outline.elements.count)"
    case .erase: "erase"
    case .fillRectangles(let paths, _): "rectfill \(paths.reduce(0) { $0 + $1.elements.count })"
    case .strokeRectangles(let paths, let matrix, _):
      "rectstroke \(paths.reduce(0) { $0 + $1.elements.count }) \(matrix == nil ? 0 : 1)"
    case .image(let image, _): "image \(image.descriptor.width) \(image.descriptor.height) \(image.components.count)"
    case .shading(let shading, _): "shading \(String(describing: shading))"
    case .form(let form, _): "form \(form.displayList.effects.count)"
    case .text(let run, _): "text \(run.glyphs.count)"
    }
  }

  private static func digest(image: RasterImage, limit: Int) throws -> String {
    let pixels = image.width.multipliedReportingOverflow(by: image.height)
    guard !pixels.overflow, pixels.partialValue <= limit else { throw ConformanceError.rasterLimitExceeded }
    var value = Data("raster-v1 \(image.width) \(image.height)\n".utf8)
    value.reserveCapacity(value.count + pixels.partialValue * 3)
    for y in 0..<image.height {
      let row = y * image.bytesPerRow
      for x in 0..<image.width {
        let pixel = row + x * 4
        value.append(image.data[pixel])
        value.append(image.data[pixel + 1])
        value.append(image.data[pixel + 2])
      }
    }
    return ConformanceDigest.sha256(value)
  }
}
