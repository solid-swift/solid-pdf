import SolidPostScript

/// Replays prepared graphics commands through a freshly created typed renderer.
public enum RasterBenchmarkReplay {
  /// Creates, drives, and finalizes one target renderer.
  public static func render<Target: GraphicsTarget>(
    _ workload: RasterRendererBenchmarkWorkload,
    to target: Target
  ) throws -> sending Target.Output {
    let renderer = try target.makeRenderer()
    do {
      for command in workload.commands {
        switch command {
        case .process(let event): try renderer.process(event)
        case .beginImage(let event): try renderer.beginImage(event)
        case .imageRows(let rows): try renderer.writeImageRows(rows)
        case .endImage: try renderer.endImage()
        }
      }
      return try renderer.finish()
    } catch {
      renderer.abort()
      throw error
    }
  }
}
