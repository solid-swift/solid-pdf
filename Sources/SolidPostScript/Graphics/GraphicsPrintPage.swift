import Foundation

/// One logical page captured once for reuse by physical copies and collated sets.
public struct GraphicsPrintPage: Sendable, Hashable {
  /// The page's zero-based index in its spool.
  public let index: Int
  /// The device state active when the page was transmitted.
  public let device: GraphicsDeviceSnapshot
  /// Realized page effects in painting order.
  public let effects: [GraphicsEffect]
  /// Transmission metadata supplied by the interpreter.
  public let transmission: GraphicsPageTransmission
  /// Whether this page requests a non-imaged inserted sheet.
  public let isInsertedSheet: Bool

  /// Creates a captured logical print page.
  public init(
    index: Int,
    device: GraphicsDeviceSnapshot,
    effects: [GraphicsEffect],
    transmission: GraphicsPageTransmission,
    isInsertedSheet: Bool = false
  ) {
    self.index = index
    self.device = device
    self.effects = effects
    self.transmission = transmission
    self.isInsertedSheet = isInsertedSheet
  }
}
