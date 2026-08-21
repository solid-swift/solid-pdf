/// A renderer-level PostScript Pattern paint.
public indirect enum GraphicsPatternPaint: Sendable, Hashable {
  /// The initial Pattern color, which produces no marks.
  case empty
  /// A tiling pattern and, for an uncolored pattern, its resolved underlying paint.
  case tiling(GraphicsTilingPattern, underlying: GraphicsPaint?)
  /// A non-tiling shading pattern.
  case shading(GraphicsShading)
}
