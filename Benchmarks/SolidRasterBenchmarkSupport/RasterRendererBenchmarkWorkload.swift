import SolidPostScript

/// An immutable renderer workload prepared entirely outside measured regions.
public struct RasterRendererBenchmarkWorkload: Sendable {
  /// One ordered renderer action.
  public enum Command: Sendable, Hashable {
    /// Processes an ordinary graphics event.
    case process(GraphicsEvent)
    /// Starts a sampled-image transfer.
    case beginImage(GraphicsEvent)
    /// Supplies complete sampled-image rows.
    case imageRows(GraphicsImageRows)
    /// Supplies complete sampled-image opacity rows.
    case imageMaskRows(GraphicsImageMaskRows)
    /// Commits the active sampled image.
    case endImage
  }

  /// Stable benchmark name shared by every backend.
  public let name: String
  /// Output width in pixels.
  public let pixelWidth: Int
  /// Output height in pixels.
  public let pixelHeight: Int
  /// Device geometry supplied to the target.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// Actions replayed for each measured iteration.
  public let commands: [Command]
  /// Whether this workload carries the acceptance threshold.
  public let enforcesPerformanceGate: Bool

  /// Creates a validated renderer workload.
  public init(
    name: String,
    pixelWidth: Int,
    pixelHeight: Int,
    deviceDescriptor: GraphicsDeviceDescriptor,
    commands: [Command],
    enforcesPerformanceGate: Bool = false
  ) throws {
    guard !name.isEmpty,
      pixelWidth > 0,
      pixelHeight > 0,
      deviceDescriptor.mediaBounds.width == Double(pixelWidth),
      deviceDescriptor.mediaBounds.height == Double(pixelHeight),
      commands.last.map(Self.transmitsPage) == true,
      Self.hasValidImageOrdering(commands)
    else { throw ValidationError.invalidFixture }
    self.name = name
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.deviceDescriptor = deviceDescriptor
    self.commands = commands
    self.enforcesPerformanceGate = enforcesPerformanceGate
  }

  /// A malformed benchmark fixture.
  public enum ValidationError: Swift.Error, Equatable, Sendable {
    case invalidFixture
  }

  private static func transmitsPage(_ command: Command) -> Bool {
    guard case .process(let event) = command else { return false }
    switch event.operation {
    case .page(.show), .page(.copy): return true
    default: return false
    }
  }

  private static func hasValidImageOrdering(_ commands: [Command]) -> Bool {
    var pendingImage: (descriptor: GraphicsImageDescriptor, nextRow: Int, nextMaskRow: Int)?
    for command in commands {
      switch command {
      case .process:
        guard pendingImage == nil else { return false }
      case .beginImage(let event):
        guard pendingImage == nil,
          case .paint(.image(let descriptor)) = event.operation,
          descriptor.width > 0,
          descriptor.height > 0
        else { return false }
        pendingImage = (descriptor, 0, 0)
      case .imageRows(let rows):
        guard var image = pendingImage,
          rows.startRow == image.nextRow,
          rows.rowCount > 0,
          rows.rowCount <= Int.max / image.descriptor.width,
          rows.rowCount * image.descriptor.width <= Int.max / image.descriptor.kind.componentCount,
          rows.components.count
            == rows.rowCount * image.descriptor.width * image.descriptor.kind.componentCount
        else { return false }
        image.nextRow += rows.rowCount
        guard image.nextRow <= image.descriptor.height else { return false }
        pendingImage = image
      case .imageMaskRows(let rows):
        guard var image = pendingImage,
          let dimensions = maskDimensions(image.descriptor),
          rows.startRow == image.nextMaskRow,
          rows.rowCount > 0,
          rows.rowCount <= Int.max / dimensions.width,
          rows.opacities.count == rows.rowCount * dimensions.width
        else { return false }
        image.nextMaskRow += rows.rowCount
        guard image.nextMaskRow <= dimensions.height else { return false }
        pendingImage = image
      case .endImage:
        guard let image = pendingImage, image.nextRow == image.descriptor.height else { return false }
        if let dimensions = maskDimensions(image.descriptor) {
          guard image.nextMaskRow == dimensions.height else { return false }
        } else {
          guard image.nextMaskRow == 0 else { return false }
        }
        pendingImage = nil
      }
    }
    return pendingImage == nil
  }

  private static func maskDimensions(_ descriptor: GraphicsImageDescriptor) -> (width: Int, height: Int)? {
    switch descriptor.mask {
    case .explicit(let width, let height, _, _): (width, height)
    case .colorKey: (descriptor.width, descriptor.height)
    case nil: nil
    }
  }
}
