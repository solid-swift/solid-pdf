/// Creates one render-scoped session for a streaming semantic graphics target.
public protocol GraphicsSemanticSink<Session>: Sendable {
  associatedtype Session: GraphicsSemanticSinkSession

  /// Creates a session that accepts the specified semantic contract version.
  func makeSession(
    contractVersion: GraphicsSemanticContractVersion
  ) throws -> sending Session
}

/// Receives the complete ordered semantic event stream for one render.
///
/// Requirements intentionally have no default implementations. A conformer must explicitly
/// account for every lifecycle and image transaction so semantic data cannot be discarded silently.
public protocol GraphicsSemanticSinkSession<Output>: AnyObject {
  associatedtype Output

  /// Activates a page or null device.
  func activateDevice(_ device: GraphicsDeviceSnapshot) throws
  /// Deactivates a page or null device.
  func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws
  /// Receives one authoritative graphics event.
  func receive(_ event: GraphicsEvent) throws
  /// Begins one sampled-image transaction after its event has been received.
  func beginImage(_ event: GraphicsEvent) throws
  /// Receives ordered color rows for the active image.
  func writeImageRows(_ rows: GraphicsImageRows) throws
  /// Receives ordered opacity rows for the active image.
  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws
  /// Completes the active image transaction.
  func endImage() throws
  /// Abandons the active image transaction.
  func abandonImage()
  /// Receives complete metadata for one page transmission.
  func transmitPage(_ event: GraphicsEvent, transmission: GraphicsPageTransmission) throws
  /// Completes a successful render.
  func finish() throws -> sending Output
  /// Abandons an unsuccessful render.
  func abandon()
}
