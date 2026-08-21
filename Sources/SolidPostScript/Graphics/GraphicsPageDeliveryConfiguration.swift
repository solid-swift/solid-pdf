import Foundation

/// Physical delivery and roll-media settings for a page device.
public struct GraphicsPageDeliveryConfiguration: Sendable, Hashable {
  /// The selected output destination, when known.
  public let destination: GraphicsOutputDestination?
  /// An unresolved output-type request for deferred selection.
  public let deferredOutputType: Data?
  /// Whether copies form complete-document page sets.
  public let collates: Bool
  /// The output stack direction.
  public let outputFace: GraphicsOutputFace
  /// When output should be jogged.
  public let jog: GraphicsJogMode
  /// Whether the selected input medium is roll-fed.
  public let isRollFed: Bool
  /// When roll media should be advanced.
  public let advanceMedia: GraphicsMediaActionMode
  /// The additional advance distance in default-user-space points.
  public let advanceDistance: Double
  /// When roll media should be cut.
  public let cutMedia: GraphicsMediaActionMode

  /// Creates a delivery configuration.
  public init(
    destination: GraphicsOutputDestination? = nil,
    deferredOutputType: Data? = nil,
    collates: Bool = false,
    outputFace: GraphicsOutputFace = .faceDown,
    jog: GraphicsJogMode = .never,
    isRollFed: Bool = false,
    advanceMedia: GraphicsMediaActionMode = .never,
    advanceDistance: Double = 0,
    cutMedia: GraphicsMediaActionMode = .never
  ) {
    self.destination = destination
    self.deferredOutputType = deferredOutputType
    self.collates = collates
    self.outputFace = outputFace
    self.jog = jog
    self.isRollFed = isRollFed
    self.advanceMedia = advanceMedia
    self.advanceDistance = advanceDistance
    self.cutMedia = cutMedia
  }

  /// Delivery behavior for an ordinary virtual page.
  public static let virtual = Self()

  var requiresPhysicalDelivery: Bool {
    destination != nil || deferredOutputType != nil || collates || outputFace == .faceUp
      || jog != .never || isRollFed || advanceMedia != .never || advanceDistance != 0 || cutMedia != .never
  }
}
