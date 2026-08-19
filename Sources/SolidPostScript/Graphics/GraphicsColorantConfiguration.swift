import Foundation
import SolidColor

/// The colorant settings selected for one page-device installation.
public struct GraphicsColorantConfiguration: Sendable, Hashable {
  public let processModel: GraphicsProcessColorModel
  public let producesSeparations: Bool
  public let additionalColorants: [GraphicsColorant]
  public let separationOrder: [String]
  public let maximumSeparations: Int
  public let supportsOverprint: Bool
  /// Optional bounded conversion from DeviceRGB into DeviceN process tints.
  public let rgbToDeviceN: ColorLookupTable?

  /// Creates a selected colorant configuration.
  public init(
    processModel: GraphicsProcessColorModel = .deviceRGB,
    producesSeparations: Bool = false,
    additionalColorants: [GraphicsColorant] = [],
    separationOrder: [String] = [],
    maximumSeparations: Int = 1,
    supportsOverprint: Bool = false,
    rgbToDeviceN: ColorLookupTable? = nil
  ) {
    self.processModel = processModel
    self.producesSeparations = producesSeparations
    self.additionalColorants = additionalColorants
    self.separationOrder = separationOrder
    self.maximumSeparations = min(250, max(1, maximumSeparations))
    self.supportsOverprint = supportsOverprint
    self.rgbToDeviceN = rgbToDeviceN
  }

  /// Process colorants followed by explicitly configured named colorants.
  public var availableColorants: [GraphicsColorant] {
    processModel.colorantNames.map {
      GraphicsColorant(name: $0, isProcessColorant: true, previewColor: Self.processPreview[$0])
    } + additionalColorants
  }

  /// The effective physical output order.
  public var effectiveSeparationOrder: [String] {
    separationOrder.isEmpty ? availableColorants.map(\.name) : separationOrder
  }

  /// Whether the DeviceN process lookup matches the configured process colorants.
  public var hasUsableDeviceNLookup: Bool {
    let processCount = additionalColorants.count(where: \.isProcessColorant)
    return rgbToDeviceN?.dimensions.count == 3
      && rgbToDeviceN?.outputComponentCount == processCount
      && processCount > 0
  }

  /// Compatibility configuration for RGB composite output.
  public static let compositeRGB = Self()

  private static let processPreview = [
    "Red": ColorRGB(red: 1, green: 0, blue: 0),
    "Green": ColorRGB(red: 0, green: 1, blue: 0),
    "Blue": ColorRGB(red: 0, green: 0, blue: 1),
    "Gray": ColorRGB(red: 0, green: 0, blue: 0),
    "Cyan": ColorRGB(red: 0, green: 1, blue: 1),
    "Magenta": ColorRGB(red: 1, green: 0, blue: 1),
    "Yellow": ColorRGB(red: 1, green: 1, blue: 0),
    "Black": ColorRGB(red: 0, green: 0, blue: 0),
  ]
}
