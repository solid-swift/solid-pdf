import Benchmark
import Foundation
import SolidPDF
import SolidPDFGraphics
import SolidPDFTextBenchmarkSupport
import SolidPostScript

let benchmarks: @Sendable () -> Void = {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResidentDelta],
    warmupIterations: 2,
    scalingFactor: .one,
    maxDuration: .seconds(10),
    maxIterations: 50
  )
  register("Long Tj Run", data: PDFTextBenchmarkFixtures.simpleRun(), configuration: configuration)
  register("Long TJ Run", data: PDFTextBenchmarkFixtures.adjustedRun(), configuration: configuration)
  register("Vertical CID Run", data: PDFTextBenchmarkFixtures.verticalRun(), configuration: configuration)
  register("Type 3 Cache Hits", data: PDFTextBenchmarkFixtures.type3Run(), configuration: configuration)
}

private func register(
  _ name: String,
  data: Data,
  configuration: Benchmark.Configuration
) {
  Benchmark(name, configuration: configuration) { benchmark in
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      let document = try await PDFDocument(source: PDFDataInputSource(data))
      let result = try await document.render(
        page: 0,
        to: RecordingGraphicsTarget(),
        fontEnvironment: PDFGraphicsFontEnvironment(providers: [PDFTextBenchmarkFixtures.FontProvider()])
      )
      blackHole(result.output.pages.count)
      await document.close()
    }
    benchmark.stopMeasurement()
  }
}
