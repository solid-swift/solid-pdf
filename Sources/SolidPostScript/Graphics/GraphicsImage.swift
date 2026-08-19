import Foundation

/// A standard device color space used by sampled image data.
public enum GraphicsImageColorSpace: Int, Sendable, Hashable {
  /// One-component DeviceGray samples.
  case deviceGray = 1
  /// Three-component DeviceRGB samples.
  case deviceRGB = 3
  /// Four-component DeviceCMYK samples.
  case deviceCMYK = 4

  /// The number of components in one sample.
  public var componentCount: Int { rawValue }
}

/// The paint interpretation of a sampled image transfer.
public enum GraphicsImageKind: Sendable, Hashable {
  /// An opaque image in a standard device color space.
  case color(GraphicsImageColorSpace)
  /// A one-component stencil mask painted with the captured graphics-state paint.
  case mask(GraphicsPaint)

  /// The number of normalized components in one transferred sample.
  public var componentCount: Int {
    switch self {
    case .color(let colorSpace): colorSpace.componentCount
    case .mask: 1
    }
  }
}

/// Immutable metadata supplied before a bounded sampled-image transfer.
public struct GraphicsImageDescriptor: Sendable, Hashable {
  /// The number of source-image columns.
  public let width: Int
  /// The number of source-image rows.
  public let height: Int
  /// The interpretation of normalized sample components.
  public let kind: GraphicsImageKind
  /// The semantic PostScript source space when samples were converted to an alternative device space.
  public let sourceColorSpace: GraphicsColorSpaceDescription?
  /// The transformation from image space to device space.
  public let imageToDevice: GraphicsMatrix
  /// Whether the target should interpolate between samples.
  public let interpolate: Bool
  /// Optional explicit or color-key masking applied by the renderer.
  public let mask: GraphicsImageMaskDescriptor?

  /// Creates an image descriptor.
  public init(
    width: Int,
    height: Int,
    kind: GraphicsImageKind,
    sourceColorSpace: GraphicsColorSpaceDescription? = nil,
    imageToDevice: GraphicsMatrix,
    interpolate: Bool = false,
    mask: GraphicsImageMaskDescriptor? = nil
  ) {
    self.width = width
    self.height = height
    self.kind = kind
    self.sourceColorSpace = sourceColorSpace
    self.imageToDevice = imageToDevice
    self.interpolate = interpolate
    self.mask = mask
  }
}

/// A bounded group of complete, normalized sampled-image rows.
public struct GraphicsImageRows: Sendable, Hashable {
  /// The zero-based source row represented by the first component.
  public let startRow: Int
  /// The number of complete rows represented by `components`.
  public let rowCount: Int
  /// Row-major normalized components in the range appropriate for the image kind.
  public let components: [Float]
  /// Original semantic source components when `components` contains a pre-evaluated alternative color.
  public let sourceComponents: [Float]?

  /// Creates a row transfer.
  public init(
    startRow: Int,
    rowCount: Int,
    components: [Float],
    sourceComponents: [Float]? = nil
  ) {
    self.startRow = startRow
    self.rowCount = rowCount
    self.components = components
    self.sourceComponents = sourceComponents
  }
}

/// A complete sampled image retained by a recording target.
public struct GraphicsImage: Sendable, Hashable {
  /// The image metadata.
  public let descriptor: GraphicsImageDescriptor
  /// All normalized components in source row order.
  public let components: [Float]
  /// Original semantic components retained by recording targets, when available.
  public let sourceComponents: [Float]?
  /// The realized opacity plane retained by recording targets, when present.
  public let mask: GraphicsImageMask?

  /// Creates a complete sampled image.
  public init(
    descriptor: GraphicsImageDescriptor,
    components: [Float],
    sourceComponents: [Float]? = nil,
    mask: GraphicsImageMask? = nil
  ) {
    self.descriptor = descriptor
    self.components = components
    self.sourceComponents = sourceComponents
    self.mask = mask
  }

  /// The number of complete source rows retained in this image.
  public var completedRowCount: Int {
    guard descriptor.width > 0 else { return 0 }
    return min(descriptor.height, components.count / (descriptor.width * descriptor.kind.componentCount))
  }

  /// Returns premultiplied RGBA8 pixels in source-row order.
  public func premultipliedRGBA8() -> Data {
    let componentCount = descriptor.kind.componentCount
    var result = Data(repeating: 0, count: descriptor.width * descriptor.height * 4)
    var destinationOffset = 0
    for offset in stride(from: 0, to: components.count, by: componentCount) {
      let red: Float
      let green: Float
      let blue: Float
      let alpha: Float
      switch descriptor.kind {
      case .color(.deviceGray):
        red = components[offset]
        green = red
        blue = red
        alpha = 1
      case .color(.deviceRGB):
        red = components[offset]
        green = components[offset + 1]
        blue = components[offset + 2]
        alpha = 1
      case .color(.deviceCMYK):
        let cyan = components[offset]
        let magenta = components[offset + 1]
        let yellow = components[offset + 2]
        let black = components[offset + 3]
        red = 1 - min(1, cyan + black)
        green = 1 - min(1, magenta + black)
        blue = 1 - min(1, yellow + black)
        alpha = 1
      case .mask(let paint):
        let rgb = paint.rgbComponents
        alpha = components[offset]
        red = Float(rgb.red) * alpha
        green = Float(rgb.green) * alpha
        blue = Float(rgb.blue) * alpha
      }
      guard destinationOffset + 3 < result.count else { break }
      result[destinationOffset] = UInt8((min(1, max(0, red)) * 255).rounded())
      result[destinationOffset + 1] = UInt8((min(1, max(0, green)) * 255).rounded())
      result[destinationOffset + 2] = UInt8((min(1, max(0, blue)) * 255).rounded())
      result[destinationOffset + 3] = UInt8((min(1, max(0, alpha)) * 255).rounded())
      destinationOffset += 4
    }
    return result
  }
}
