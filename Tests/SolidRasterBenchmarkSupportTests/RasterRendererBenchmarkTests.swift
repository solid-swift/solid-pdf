import SolidPostScript
import SolidPostScriptPlutoVG
import SolidPostScriptRaster
import SolidRaster
import SolidRasterBenchmarkSupport
import Testing

@Suite struct RasterRendererBenchmarkTests {
  @Test func workloadsHaveStableNamesAndCommandOrdering() throws {
    let workloads = try RasterRendererBenchmarkFixtures.all()

    #expect(workloads.map(\.name) == RasterRendererBenchmarkFixtures.names)
    #expect(workloads.filter(\.enforcesPerformanceGate).map(\.name) == ["Combined Path-Heavy Page"])
    for workload in workloads {
      guard case .process(let finalEvent) = workload.commands.last else {
        Issue.record("The final command must transmit a page")
        continue
      }
      #expect(finalEvent.operation == .page(.show))
    }

    let image = try #require(workloads.first { $0.name == "8 MP Nearest Image" })
    guard case .beginImage = image.commands.first else {
      Issue.record("Image workload must begin with image metadata")
      return
    }
    #expect(image.commands.contains(.endImage))
  }

  @Test func invalidFixturesAreRejectedTransactionally() {
    let descriptor = device(width: 10, height: 10)
    #expect(throws: RasterRendererBenchmarkWorkload.ValidationError.invalidFixture) {
      try RasterRendererBenchmarkWorkload(
        name: "",
        pixelWidth: 10,
        pixelHeight: 10,
        deviceDescriptor: descriptor,
        commands: []
      )
    }

    let state = state(width: 10, height: 10)
    let image = GraphicsImageDescriptor(
      width: 1,
      height: 1,
      kind: .color(.deviceGray),
      imageToDevice: .identity
    )
    let begin = GraphicsEvent(operation: .paint(.image(image)), before: state, after: state)
    let page = GraphicsEvent(operation: .page(.show), before: state, after: state)
    #expect(throws: RasterRendererBenchmarkWorkload.ValidationError.invalidFixture) {
      try RasterRendererBenchmarkWorkload(
        name: "incomplete image",
        pixelWidth: 10,
        pixelHeight: 10,
        deviceDescriptor: descriptor,
        commands: [.beginImage(begin), .process(page)]
      )
    }
  }

  @Test func nativeAndPlutoReplayTheSamePreparedPage() throws {
    let workload = try smallFillWorkload()
    let native = try RasterBenchmarkReplay.render(
      workload,
      to: RasterImageTarget(
        pixelWidth: workload.pixelWidth,
        pixelHeight: workload.pixelHeight,
        deviceDescriptor: workload.deviceDescriptor
      )
    )
    let pluto = try RasterBenchmarkReplay.render(
      workload,
      to: PlutoVGImageTarget(
        pixelWidth: workload.pixelWidth,
        pixelHeight: workload.pixelHeight,
        deviceDescriptor: workload.deviceDescriptor
      )
    )

    #expect(native.count == 1)
    #expect(pluto.count == 1)
    let nativeGray = try gray(x: 20, y: 20, image: #require(native.first))
    let plutoGray = try gray(x: 20, y: 20, image: #require(pluto.first))
    #expect(abs(nativeGray - plutoGray) < 0.02)
  }

  private func smallFillWorkload() throws -> RasterRendererBenchmarkWorkload {
    let descriptor = device(width: 40, height: 40)
    let path = GraphicsPath(elements: [
      .move(to: GraphicsPoint(x: 5, y: 5)),
      .line(to: GraphicsPoint(x: 35, y: 5)),
      .line(to: GraphicsPoint(x: 35, y: 35)),
      .line(to: GraphicsPoint(x: 5, y: 35)),
      .close,
    ])
    let before = GraphicsStateSnapshot(
      matrix: .identity,
      path: path,
      clip: GraphicsClip(imageableBounds: descriptor.imageableBounds),
      paint: .deviceGray(0.25),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
    let after = state(width: 40, height: 40)
    return try RasterRendererBenchmarkWorkload(
      name: "small fill",
      pixelWidth: 40,
      pixelHeight: 40,
      deviceDescriptor: descriptor,
      commands: [
        .process(GraphicsEvent(operation: .paint(.fill(.winding)), before: before, after: after)),
        .process(GraphicsEvent(operation: .page(.show), before: after, after: after)),
      ]
    )
  }

  private func state(width: Int, height: Int) -> GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: .identity,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: device(width: width, height: height).imageableBounds),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
  }

  private func device(width: Int, height: Int) -> GraphicsDeviceDescriptor {
    let bounds = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    return GraphicsDeviceDescriptor(
      mediaBounds: bounds,
      imageableBounds: bounds,
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    )
  }

  private func gray(x: Int, y: Int, image: RasterImage) throws -> Double {
    let offset = y * image.bytesPerRow + x * 4
    guard offset >= 0, offset + 3 < image.data.count else {
      throw RasterRendererBenchmarkWorkload.ValidationError.invalidFixture
    }
    return Double(image.data[offset]) / 255
  }
}
