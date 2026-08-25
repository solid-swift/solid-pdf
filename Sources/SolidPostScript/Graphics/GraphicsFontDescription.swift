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
  /// The language-visible font technology.
  public let technology: GraphicsFontTechnology
  /// The PostScript FontType value, when known.
  public let fontType: Int?
  /// The PostScript PaintType value.
  public let paintType: Int
  /// The design-space stroke width used by PaintType 2 fonts.
  public let strokeWidth: Double
  /// The identity of this immutable language-visible font instance.
  public let resourceIdentifier: GraphicsResourceIdentifier
  /// Provider-substitution evidence for a PDF font, when applicable.
  public let substitution: GraphicsFontSubstitution?

  /// Creates a portable font description.
  public init(
    identifier: GraphicsFontIdentifier,
    resourceName: String? = nil,
    postScriptName: String? = nil,
    matrix: GraphicsMatrix = .identity,
    writingMode: Int = 0,
    asset: FontAsset? = nil,
    outlineAccess: FontOutlineAccess = .extractable,
    technology: GraphicsFontTechnology = .unknown,
    fontType: Int? = nil,
    paintType: Int = 0,
    strokeWidth: Double = 0,
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous,
    substitution: GraphicsFontSubstitution? = nil
  ) {
    self.identifier = identifier
    self.resourceName = resourceName
    self.postScriptName = postScriptName
    self.matrix = matrix
    self.writingMode = writingMode
    self.asset = asset
    self.outlineAccess = outlineAccess
    self.technology = technology
    self.fontType = fontType
    self.paintType = paintType
    self.strokeWidth = strokeWidth
    self.resourceIdentifier = resourceIdentifier
    self.substitution = substitution
  }

  /// The invalid font installed in a new graphics state.
  public static let invalid = Self(identifier: .invalid)
}
