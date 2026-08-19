import Foundation
import SolidColor

/// One process or named device colorant.
public struct GraphicsColorant: Sendable, Hashable {
  /// The PostScript colorant name.
  public let name: String
  /// Whether the colorant belongs to the device process model.
  public let isProcessColorant: Bool
  /// A diagnostic additive RGB preview color for maximum tint.
  public let previewColor: ColorRGB?

  /// Creates a device colorant.
  public init(name: String, isProcessColorant: Bool, previewColor: ColorRGB? = nil) {
    self.name = name
    self.isProcessColorant = isProcessColorant
    self.previewColor = previewColor
  }
}
