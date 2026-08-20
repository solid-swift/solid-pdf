import Foundation

/// Attributes describing requested or available physical media.
public struct GraphicsMediaAttributes: Sendable, Hashable {
  /// The media dimensions in default-user-space points.
  public var pageSize: GraphicsSize?
  /// The exact PostScript byte string identifying the media color.
  public var color: Data?
  /// The media weight in grams per square meter.
  public var weight: Double?
  /// The exact PostScript byte string identifying the media type.
  public var type: Data?
  /// The exact PostScript byte string identifying the media class.
  public var mediaClass: Data?
  /// Whether the medium bypasses the imaging mechanism.
  public var insertsSheet: Bool?

  /// Creates a media-attribute value.
  public init(
    pageSize: GraphicsSize? = nil,
    color: Data? = nil,
    weight: Double? = nil,
    type: Data? = nil,
    mediaClass: Data? = nil,
    insertsSheet: Bool? = nil
  ) {
    self.pageSize = pageSize
    self.color = color
    self.weight = weight
    self.type = type
    self.mediaClass = mediaClass
    self.insertsSheet = insertsSheet
  }
}
