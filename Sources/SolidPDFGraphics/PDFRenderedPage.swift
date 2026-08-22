import SolidPDF
import SolidPostScript

/// Metadata for one successfully transmitted PDF page.
public struct PDFRenderedPage: Sendable, Hashable {
  /// The selected revision.
  public let revision: PDFRevisionIdentifier
  /// The zero-based source page index.
  public let pageIndex: Int
  /// The source page object.
  public let pageReference: PDFObjectReference
  /// The activated target device.
  public let device: GraphicsDeviceSnapshot
  /// Exact page-point and device-space conversion.
  public let coordinateMapping: GraphicsPageCoordinateMapping
  /// The zero-based transmission ordinal in this result.
  public let transmittedOrdinal: Int

  /// Creates rendered-page metadata.
  public init(
    revision: PDFRevisionIdentifier,
    pageIndex: Int,
    pageReference: PDFObjectReference,
    device: GraphicsDeviceSnapshot,
    coordinateMapping: GraphicsPageCoordinateMapping,
    transmittedOrdinal: Int
  ) {
    self.revision = revision
    self.pageIndex = pageIndex
    self.pageReference = pageReference
    self.device = device
    self.coordinateMapping = coordinateMapping
    self.transmittedOrdinal = transmittedOrdinal
  }
}
