import Foundation

/// An immutable, backend-independent font asset.
public struct FontAsset: Sendable, Hashable {
  /// A supported font container or PostScript font representation.
  public enum Format: Sendable, Hashable {
    /// An Adobe Type 1 font program or decoded font dictionary payload.
    case type1
    /// A Compact Font Format font or font set.
    case compactFontFormat
    /// An sfnt-based TrueType or OpenType font.
    case sfnt
    /// A PostScript Type 3 procedure font with no external binary asset.
    case type3
    /// A backend-defined Chameleon font.
    case chameleon
  }

  /// The immutable font metadata.
  public let descriptor: FontDescriptor
  /// The declared asset format.
  public let format: Format
  /// The complete binary data, when the format has an external representation.
  public let data: Data?
  /// The face index within a font collection.
  public let faceIndex: Int

  /// Creates a portable font asset.
  public init(
    descriptor: FontDescriptor,
    format: Format,
    data: Data? = nil,
    faceIndex: Int = 0
  ) throws {
    guard faceIndex >= 0 else { throw FontError.range }
    if format != .type3, data == nil { throw FontError.invalidData }
    self.descriptor = descriptor
    self.format = format
    self.data = data
    self.faceIndex = faceIndex
  }
}
