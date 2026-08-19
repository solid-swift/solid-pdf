import Foundation

/// A render-scoped virtual page-device session.
public final class StandardGraphicsPageDeviceSession: GraphicsPageDeviceSession, Sendable {
  /// The target's supported geometry and resource limits.
  public let capabilities: GraphicsPageDeviceCapabilities
  /// The settings active when the render begins.
  public let initialConfiguration: GraphicsPageDeviceConfiguration

  private let initialPageSize: GraphicsSize
  private let initialResolution: GraphicsSize
  private let initialDescriptor: GraphicsDeviceDescriptor
  private let margins: (left: Double, bottom: Double, right: Double, top: Double)
  private let name: String

  init(
    descriptor: GraphicsDeviceDescriptor,
    capabilities: GraphicsPageDeviceCapabilities,
    name: String
  ) throws {
    guard descriptor.horizontalResolution.isFinite,
      descriptor.verticalResolution.isFinite,
      descriptor.horizontalResolution > 0,
      descriptor.verticalResolution > 0
    else { throw GraphicsPageDeviceError.invalidConfiguration }
    let resolution = GraphicsSize(
      width: descriptor.horizontalResolution,
      height: descriptor.verticalResolution
    )
    let pageSize = GraphicsSize(
      width: descriptor.mediaBounds.width * 72 / resolution.width,
      height: descriptor.mediaBounds.height * 72 / resolution.height
    )
    guard Self.valid(pageSize), Self.valid(resolution) else {
      throw GraphicsPageDeviceError.invalidConfiguration
    }
    let left = (descriptor.imageableBounds.x - descriptor.mediaBounds.x) * 72 / resolution.width
    let bottom = (descriptor.imageableBounds.y - descriptor.mediaBounds.y) * 72 / resolution.height
    let right = (descriptor.mediaBounds.maxX - descriptor.imageableBounds.maxX) * 72 / resolution.width
    let top = (descriptor.mediaBounds.maxY - descriptor.imageableBounds.maxY) * 72 / resolution.height
    self.capabilities = capabilities
    self.initialPageSize = pageSize
    self.initialResolution = resolution
    self.initialDescriptor = descriptor
    self.margins = (left, bottom, right, top)
    self.name = name
    self.initialConfiguration = GraphicsPageDeviceConfiguration(
      identifier: GraphicsDeviceIdentifier(),
      pageSize: pageSize,
      imagingBoundingBox: nil,
      numberOfCopies: 1,
      name: name,
      descriptor: descriptor
    )
  }

  /// Negotiates requested settings against the session's target capabilities.
  public func negotiate(_ request: GraphicsPageDeviceRequest) throws -> GraphicsPageDeviceNegotiation {
    guard Self.valid(request.pageSize),
      Self.valid(request.resolution),
      request.numberOfCopies.map({ $0 >= 0 }) ?? true,
      request.imagingBoundingBox.map(Self.valid) ?? true
    else { throw GraphicsPageDeviceError.invalidConfiguration }

    var unsatisfied: Set<String> = []
    let selectedPageSize: GraphicsSize
    let selectedResolution: GraphicsSize
    switch capabilities.mode {
    case .adaptive:
      selectedPageSize = request.pageSize
      selectedResolution = request.resolution
    case .fixed:
      selectedPageSize = initialPageSize
      selectedResolution = initialResolution
      if request.pageSize != initialPageSize { unsatisfied.insert("PageSize") }
      if request.resolution != initialResolution { unsatisfied.insert("HWResolution") }
    }

    let descriptor = try makeDescriptor(pageSize: selectedPageSize, resolution: selectedResolution)
    return GraphicsPageDeviceNegotiation(
      configuration: GraphicsPageDeviceConfiguration(
        identifier: GraphicsDeviceIdentifier(),
        pageSize: selectedPageSize,
        imagingBoundingBox: request.imagingBoundingBox,
        numberOfCopies: request.numberOfCopies,
        name: name,
        descriptor: descriptor
      ),
      unsatisfiedParameters: unsatisfied
    )
  }

  private func makeDescriptor(
    pageSize: GraphicsSize,
    resolution: GraphicsSize
  ) throws -> GraphicsDeviceDescriptor {
    if capabilities.mode == .fixed { return initialDescriptor }
    let pixelWidth = pageSize.width * resolution.width / 72
    let pixelHeight = pageSize.height * resolution.height / 72
    guard pixelWidth.isFinite, pixelHeight.isFinite,
      pixelWidth <= Double(Int.max), pixelHeight <= Double(Int.max)
    else { throw GraphicsPageDeviceError.limitExceeded }
    let width = max(1, Int(pixelWidth.rounded(.toNearestOrAwayFromZero)))
    let height = max(1, Int(pixelHeight.rounded(.toNearestOrAwayFromZero)))
    guard width <= capabilities.maximumPixelWidth,
      height <= capabilities.maximumPixelHeight,
      width <= Int.max / 4,
      height <= Int.max / (width * 4),
      width * height * 4 <= capabilities.maximumSurfaceBytes
    else { throw GraphicsPageDeviceError.limitExceeded }

    let media = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    let imageable = GraphicsRect(
      x: margins.left * resolution.width / 72,
      y: margins.bottom * resolution.height / 72,
      width: max(0, Double(width) - (margins.left + margins.right) * resolution.width / 72),
      height: max(0, Double(height) - (margins.bottom + margins.top) * resolution.height / 72)
    )
    return GraphicsDeviceDescriptor(
      mediaBounds: media,
      imageableBounds: imageable,
      horizontalResolution: resolution.width,
      verticalResolution: resolution.height,
      defaultMatrix: GraphicsMatrix(
        a: resolution.width / 72,
        b: 0,
        c: 0,
        d: resolution.height / 72,
        tx: 0,
        ty: 0
      ),
      defaultFlatness: initialDescriptor.defaultFlatness,
      defaultStrokeAdjustment: initialDescriptor.defaultStrokeAdjustment,
      minimumSmoothness: initialDescriptor.minimumSmoothness,
      maximumSmoothness: initialDescriptor.maximumSmoothness,
      defaultSmoothness: initialDescriptor.defaultSmoothness,
      colorDevice: initialDescriptor.colorDevice
    )
  }

  private static func valid(_ size: GraphicsSize) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
  }

  private static func valid(_ rect: GraphicsRect) -> Bool {
    rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
      && rect.width >= 0 && rect.height >= 0
  }
}
