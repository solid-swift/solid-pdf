import Foundation

/// Limits applied while parsing untrusted font programs.
public struct FontParsingLimits: Sendable, Hashable {
  /// The largest complete font program accepted by a parser.
  public let maximumDataBytes: Int
  /// The largest number of objects accepted in one font collection.
  public let maximumObjects: Int
  /// The largest number of glyph programs accepted in one face.
  public let maximumGlyphs: Int
  /// The largest combined byte count accepted for one INDEX structure.
  public let maximumIndexBytes: Int
  /// The largest operand stack accepted by a font program.
  public let maximumOperandStack: Int
  /// The largest nested subroutine depth accepted by a glyph program.
  public let maximumSubroutineDepth: Int
  /// The largest number of outline elements produced by one glyph.
  public let maximumOutlineElements: Int

  /// Creates a set of bounded font-program limits.
  public init(
    maximumDataBytes: Int = 64 * 1_024 * 1_024,
    maximumObjects: Int = 1_000_000,
    maximumGlyphs: Int = 1_000_000,
    maximumIndexBytes: Int = 64 * 1_024 * 1_024,
    maximumOperandStack: Int = 96,
    maximumSubroutineDepth: Int = 10,
    maximumOutlineElements: Int = 1_000_000
  ) throws {
    guard maximumDataBytes > 0, maximumObjects > 0, maximumGlyphs > 0,
      maximumIndexBytes > 0, maximumOperandStack > 0, maximumSubroutineDepth >= 0,
      maximumOutlineElements > 0
    else { throw FontError.range }
    self.maximumDataBytes = maximumDataBytes
    self.maximumObjects = maximumObjects
    self.maximumGlyphs = maximumGlyphs
    self.maximumIndexBytes = maximumIndexBytes
    self.maximumOperandStack = maximumOperandStack
    self.maximumSubroutineDepth = maximumSubroutineDepth
    self.maximumOutlineElements = maximumOutlineElements
  }

  /// Conservative defaults suitable for interpreter-controlled font loading.
  public static let `default` = try! FontParsingLimits()
}
