import Foundation
import SolidFont

/// A stable identity for one language-visible font instance.
public struct GraphicsFontIdentifier: Sendable, Hashable {
  /// The stable identifier value.
  public let value: String

  /// Creates a font identifier.
  public init(_ value: String) {
    self.value = value
  }

  /// The invalid initial font.
  public static let invalid = Self("@InvalidFont")
}

/// A portable description of the current PostScript font.
public struct GraphicsFontDescription: Sendable, Hashable {
  /// The font's language-visible identity.
  public let identifier: GraphicsFontIdentifier
  /// The requested resource name, when known.
  public let resourceName: String?
  /// The resolved PostScript font name, when known.
  public let postScriptName: String?
  /// The font matrix applied before the CTM.
  public let matrix: GraphicsMatrix
  /// The writing mode, where zero is horizontal and one is vertical.
  public let writingMode: Int
  /// A portable binary asset when one is available.
  public let asset: FontAsset?
  /// Whether glyph outlines may be exposed through PostScript path inspection.
  public let outlineAccess: FontOutlineAccess

  /// Creates a portable font description.
  public init(
    identifier: GraphicsFontIdentifier,
    resourceName: String? = nil,
    postScriptName: String? = nil,
    matrix: GraphicsMatrix = .identity,
    writingMode: Int = 0,
    asset: FontAsset? = nil,
    outlineAccess: FontOutlineAccess = .extractable
  ) {
    self.identifier = identifier
    self.resourceName = resourceName
    self.postScriptName = postScriptName
    self.matrix = matrix
    self.writingMode = writingMode
    self.asset = asset
    self.outlineAccess = outlineAccess
  }

  /// The invalid font installed in a new graphics state.
  public static let invalid = Self(identifier: .invalid)
}
