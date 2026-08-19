import Foundation

/// Creates target-specific font preparation state for one render.
public protocol GraphicsFontEngine<Session>: Sendable {
  associatedtype Session: GraphicsFontSession

  /// Creates isolated font preparation state for `device`.
  func makeSession(for device: GraphicsDeviceDescriptor) throws -> sending Session
}

/// Prepares semantic fonts and glyphs for one renderer without type erasure.
public protocol GraphicsFontSession<PreparedFont, PreparedGlyph>: AnyObject {
  associatedtype PreparedFont
  associatedtype PreparedGlyph

  /// Prepares a semantic font for a target-specific fast path.
  func prepare(_ font: GraphicsFontDescription) throws -> PreparedFont?
  /// Prepares one glyph in a previously prepared font.
  func prepare(
    _ glyph: GraphicsGlyphDescription,
    in font: borrowing PreparedFont
  ) throws -> PreparedGlyph?
}

/// The compatibility engine that preserves portable font and glyph values.
public struct SemanticGraphicsFontEngine: GraphicsFontEngine, Sendable {
  /// Creates a semantic font engine.
  public init() {}

  /// Creates one semantic font session.
  public func makeSession(for device: GraphicsDeviceDescriptor) -> sending SemanticGraphicsFontSession {
    SemanticGraphicsFontSession()
  }
}

/// A semantic session used by recording, null, and compatibility targets.
public final class SemanticGraphicsFontSession: GraphicsFontSession {
  /// Creates a semantic font session.
  public init() {}

  /// Returns the portable font unchanged.
  public func prepare(_ font: GraphicsFontDescription) -> GraphicsFontDescription? { font }

  /// Returns the portable glyph unchanged.
  public func prepare(
    _ glyph: GraphicsGlyphDescription,
    in font: borrowing GraphicsFontDescription
  ) -> GraphicsGlyphDescription? {
    glyph
  }
}
