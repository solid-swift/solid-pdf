import SolidColor

/// The target-independent geometry retained for a PostScript shading.
public enum GraphicsShadingGeometry: Sendable, Hashable {
  /// A function-based rectangular domain and its mapping into shading space.
  case function(domain: GraphicsRect, matrix: GraphicsMatrix, functions: [ColorFunction])
  /// An axial gradient.
  case axial(
    start: GraphicsPoint,
    end: GraphicsPoint,
    domainStart: Double,
    domainEnd: Double,
    extendStart: Bool,
    extendEnd: Bool,
    functions: [ColorFunction]
  )
  /// A radial gradient between two circles.
  case radial(
    startCenter: GraphicsPoint,
    startRadius: Double,
    endCenter: GraphicsPoint,
    endRadius: Double,
    domainStart: Double,
    domainEnd: Double,
    extendStart: Bool,
    extendEnd: Bool,
    functions: [ColorFunction]
  )
  /// A decoded free-form or lattice triangle mesh.
  case triangles(type: Int, vertexCount: Int)
  /// A decoded Coons or tensor-product patch mesh.
  case patches(type: Int, patchCount: Int)
}

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
  /// The optional shading-space bounds resolved into device coordinates.
  public let clipPath: GraphicsPath?
  /// Whether the target may apply additional antialiasing.
  public let antialias: Bool
  /// The original validated gradient geometry.
  public let geometry: GraphicsShadingGeometry
  /// The portable fallback geometry and colors.
  public let mesh: GraphicsShadingMesh

  /// Creates a semantic shading.
  public init(
    type: Int,
    colorSpace: GraphicsColorSpaceDescription,
    background: GraphicsPaint? = nil,
    bounds: GraphicsRect? = nil,
    clipPath: GraphicsPath? = nil,
    antialias: Bool = false,
    geometry: GraphicsShadingGeometry,
    mesh: GraphicsShadingMesh
  ) {
    self.type = type
    self.colorSpace = colorSpace
    self.background = background
    self.bounds = bounds
    self.clipPath = clipPath
    self.antialias = antialias
    self.geometry = geometry
    self.mesh = mesh
  }
}
