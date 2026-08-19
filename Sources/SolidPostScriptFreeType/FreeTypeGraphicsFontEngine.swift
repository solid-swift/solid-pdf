#if os(Linux)
import CFreeType
import Foundation
import SolidPostScript

/// A renderer-owned FreeType face token.
public struct FreeTypePreparedFont: Hashable, Sendable {
  /// The semantic font identity corresponding to the prepared face.
  public let identifier: GraphicsFontIdentifier
}

/// A glyph prepared for an optional FreeType renderer fast path.
public struct FreeTypePreparedGlyph: Hashable, Sendable {
  /// The exact glyph index selected by the PostScript interpreter.
  public let index: UInt32
  /// The portable description retained for non-equivalent rendering paths.
  public let fallback: GraphicsGlyphDescription
}

/// Creates renderer-owned FreeType preparation sessions.
public struct FreeTypeGraphicsFontEngine: GraphicsFontEngine, Sendable {
  /// Creates a FreeType graphics font engine.
  public init() {}

  /// Creates a session with one isolated FreeType library and face cache.
  public func makeSession(for device: GraphicsDeviceDescriptor) throws -> sending FreeTypeGraphicsFontSession {
    try FreeTypeGraphicsFontSession()
  }
}

/// Owns memory-backed FreeType faces for exactly one renderer.
public final class FreeTypeGraphicsFontSession: GraphicsFontSession {
  private final class Face {
    let data: NSData
    let pointer: FT_Face

    init(data: NSData, pointer: FT_Face) {
      self.data = data
      self.pointer = pointer
    }

    deinit { FT_Done_Face(pointer) }
  }

  private let library: FT_Library
  private var faces: [GraphicsFontIdentifier: Face] = [:]

  /// Creates a renderer-owned FreeType library.
  public init() throws {
    var value: FT_Library?
    guard FT_Init_FreeType(&value) == 0, let value else { throw Error.ioError }
    library = value
  }

  deinit {
    faces.removeAll()
    FT_Done_FreeType(library)
  }

  /// Creates and caches a memory-backed face for a portable asset.
  public func prepare(_ font: GraphicsFontDescription) throws -> FreeTypePreparedFont? {
    if faces[font.identifier] != nil { return FreeTypePreparedFont(identifier: font.identifier) }
    guard let asset = font.asset, let data = asset.data else { return nil }
    let ownedData = data as NSData
    var face: FT_Face?
    guard FT_New_Memory_Face(
      library,
      ownedData.bytes.assumingMemoryBound(to: UInt8.self),
      ownedData.length,
      asset.faceIndex,
      &face
    ) == 0 else { return nil }
    guard let face else { return nil }
    faces[font.identifier] = Face(data: ownedData, pointer: face)
    return FreeTypePreparedFont(identifier: font.identifier)
  }

  /// Prepares the interpreter-selected glyph without backend character mapping.
  public func prepare(
    _ glyph: GraphicsGlyphDescription,
    in font: borrowing FreeTypePreparedFont
  ) throws -> FreeTypePreparedGlyph? {
    guard let face = faces[font.identifier] else { return nil }
    let index: UInt32
    switch glyph.selector {
    case .index(let value), .cid(let value):
      index = value
    case .name(let name):
      let value = name.withCString { FT_Get_Name_Index(face.pointer, $0) }
      guard value != 0 || name == ".notdef" else { return nil }
      index = UInt32(value)
    case .character:
      return nil
    }
    return FreeTypePreparedGlyph(index: index, fallback: glyph)
  }
}
#endif
