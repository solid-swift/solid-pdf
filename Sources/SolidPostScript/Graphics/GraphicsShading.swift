/// A semantic PostScript shading with a deterministic portable fallback mesh.
public struct GraphicsShading: Sendable, Hashable {
  /// The LanguageLevel 3 shading type (`1...7`).
  public let type: Int
  /// The non-Pattern source color space.
  public let colorSpace: GraphicsColorSpaceDescription
  /// The optional color painted outside the defined shading domain.
  public let background: GraphicsPaint?
  /// The optional user-space clipping bounds.
  public let bounds: GraphicsRect?
  /// Whether the target may apply additional antialiasing.
  public let antialias: Bool
  /// The portable fallback geometry and colors.
  public let mesh: GraphicsShadingMesh

  /// Creates a semantic shading.
  public init(
    type: Int,
    colorSpace: GraphicsColorSpaceDescription,
    background: GraphicsPaint? = nil,
    bounds: GraphicsRect? = nil,
    antialias: Bool = false,
    mesh: GraphicsShadingMesh
  ) {
    self.type = type
    self.colorSpace = colorSpace
    self.background = background
    self.bounds = bounds
    self.antialias = antialias
    self.mesh = mesh
  }
}
