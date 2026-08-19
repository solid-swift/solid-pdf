import Foundation

/// Geometry and coordinate-system information supplied by a graphics target.
public struct GraphicsDeviceDescriptor: Sendable, Hashable {
  /// The complete page bounds in device space.
  public let mediaBounds: GraphicsRect
  /// The initially imageable page bounds in device space.
  public let imageableBounds: GraphicsRect
  /// The horizontal device resolution in dots per inch.
  public let horizontalResolution: Double
  /// The vertical device resolution in dots per inch.
  public let verticalResolution: Double
  /// The initial transformation from default user space to device space.
  public let defaultMatrix: GraphicsMatrix
  /// The initial curve-flattening tolerance in device pixels.
  public let defaultFlatness: Double
  /// Whether stroke adjustment is initially enabled.
  public let defaultStrokeAdjustment: Bool
  /// The smallest smoothness value the device can achieve.
  public let minimumSmoothness: Double
  /// The largest smoothness value the device can achieve.
  public let maximumSmoothness: Double
  /// The initial shading smoothness.
  public let defaultSmoothness: Double
  /// The target's process-color and destination-profile capabilities.
  public let colorDevice: GraphicsColorDeviceDescriptor
  /// The target's transfer, quantization, and halftone capabilities.
  public let deviceRendering: GraphicsDeviceRenderingDescriptor
  /// The selected process and named-colorant configuration.
  public let colorants: GraphicsColorantConfiguration

  /// Creates a graphics device descriptor.
  public init(
    mediaBounds: GraphicsRect,
    imageableBounds: GraphicsRect,
    horizontalResolution: Double,
    verticalResolution: Double,
    defaultMatrix: GraphicsMatrix,
    defaultFlatness: Double = 1,
    defaultStrokeAdjustment: Bool = false,
    minimumSmoothness: Double = 1 / 255,
    maximumSmoothness: Double = 1,
    defaultSmoothness: Double = 0.02,
    colorDevice: GraphicsColorDeviceDescriptor = .sRGB,
    deviceRendering: GraphicsDeviceRenderingDescriptor = .continuousTone,
    colorants: GraphicsColorantConfiguration = .compositeRGB
  ) {
    self.mediaBounds = mediaBounds
    self.imageableBounds = imageableBounds
    self.horizontalResolution = horizontalResolution
    self.verticalResolution = verticalResolution
    self.defaultMatrix = defaultMatrix
    self.defaultFlatness = defaultFlatness
    self.defaultStrokeAdjustment = defaultStrokeAdjustment
    self.minimumSmoothness = minimumSmoothness
    self.maximumSmoothness = maximumSmoothness
    self.defaultSmoothness = defaultSmoothness
    self.colorDevice = colorDevice
    self.deviceRendering = deviceRendering
    self.colorants = colorants
  }

  /// The installation-default Letter page at 72 dots per inch.
  public static let letter = Self(
    mediaBounds: GraphicsRect(x: 0, y: 0, width: 612, height: 792),
    imageableBounds: GraphicsRect(x: 0, y: 0, width: 612, height: 792),
    horizontalResolution: 72,
    verticalResolution: 72,
    defaultMatrix: .identity
  )
}
