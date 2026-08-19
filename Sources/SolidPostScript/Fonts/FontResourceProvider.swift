import Foundation
import SolidFont

/// A backend-independent query for a host or application font resource.
public struct FontResourceQuery: Sendable, Hashable {
  /// The requested PostScript resource name.
  public let name: String
  /// Whether Standard 35 substitution may be used.
  public let permitsSubstitution: Bool

  /// Creates a font-resource query.
  public init(name: String, permitsSubstitution: Bool = true) {
    self.name = name
    self.permitsSubstitution = permitsSubstitution
  }
}

/// A font face returned by a resource provider without retaining PostScript objects.
public struct FontProviderFace: Sendable, Hashable {
  /// The provider that owns the face key.
  public let providerIdentifier: String
  /// The provider-specific stable face key.
  public let faceKey: String
  /// Portable font metadata and optional data.
  public let asset: FontAsset
  /// Whether the provider substituted another host face.
  public let isSubstitute: Bool

  /// Creates a provider face.
  public init(
    providerIdentifier: String,
    faceKey: String,
    asset: FontAsset,
    isSubstitute: Bool = false
  ) {
    self.providerIdentifier = providerIdentifier
    self.faceKey = faceKey
    self.asset = asset
    self.isSubstitute = isSubstitute
  }
}

/// Discovers host fonts and materializes portable glyph programs.
public protocol FontResourceProvider: Sendable {
  /// A stable identifier unique within an interpreter environment.
  var identifier: String { get }
  /// Names available for external resource enumeration.
  func availableFontNames() async throws -> [String]
  /// Resolves an exact or permitted substitute face.
  func resolve(_ query: FontResourceQuery) async throws -> FontProviderFace?
  /// Resolves one glyph from a previously returned face.
  func glyph(_ selector: FontGlyphSelector, in face: FontProviderFace) async throws -> FontGlyph?
  /// Whether this provider can execute FontType 14 Chameleon fonts.
  var supportsChameleonFonts: Bool { get }
}

extension FontResourceProvider {
  /// Providers do not support Chameleon fonts unless they opt in explicitly.
  public var supportsChameleonFonts: Bool { false }
}
