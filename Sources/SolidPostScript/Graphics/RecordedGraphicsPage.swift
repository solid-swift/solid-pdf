import Foundation

/// One page transmitted by a recording graphics target.
public struct RecordedGraphicsPage: Sendable, Hashable {
  /// The graphics device used for the page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The complete device state active when this page was transmitted.
  public let device: GraphicsDeviceSnapshot
  /// The logical transmission that produced this page.
  public let transmission: GraphicsPageTransmission
  /// The one-based copy represented by this page.
  public let copyOrdinal: Int
  /// Exact conversion between page points and device coordinates.
  public let coordinateMapping: GraphicsPageCoordinateMapping
  /// The realized effects in painting order.
  public let effects: [GraphicsEffect]
  /// The trapping zones and parameters active when the page was transmitted.
  public let trapping: GraphicsTrappingSnapshot

  /// Creates a recorded page.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor,
    effects: [GraphicsEffect],
    trapping: GraphicsTrappingSnapshot = .disabled,
    device: GraphicsDeviceSnapshot? = nil,
    transmission: GraphicsPageTransmission = .init(
      trigger: .showPage,
      logicalOrdinal: 1,
      copies: 1
    ),
    copyOrdinal: Int = 1
  ) {
    let resolvedDevice = device ?? GraphicsDeviceSnapshot(
      identifier: GraphicsDeviceIdentifier(),
      kind: .page,
      descriptor: deviceDescriptor,
      pageNumber: 0,
      numberOfCopies: transmission.copies,
      trapping: trapping
    )
    self.deviceDescriptor = deviceDescriptor
    self.device = resolvedDevice
    self.transmission = transmission
    self.copyOrdinal = copyOrdinal
    self.coordinateMapping = GraphicsPageCoordinateMapping(device: resolvedDevice.descriptor)
    self.effects = effects
    self.trapping = trapping
  }
}
