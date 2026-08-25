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
  /// Identity shared by repeated references to this shading instance.
  public let resourceIdentifier: GraphicsResourceIdentifier
  /// The LanguageLevel 3 shading type (`1...7`).
  public let type: Int
  /// The non-Pattern source color space.
  public let colorSpace: GraphicsColorSpaceDescription
  /// Immutable realization data for the shading's selected color space.
  public let colorRealization: GraphicsColorSpaceRealization?
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
  /// Exact reconstructed source patches for Type 6 and Type 7 shadings.
  public let sourcePatches: [GraphicsShadingPatch]

  /// Creates a semantic shading.
  public init(
    type: Int,
    colorSpace: GraphicsColorSpaceDescription,
    colorRealization: GraphicsColorSpaceRealization? = nil,
    background: GraphicsPaint? = nil,
    bounds: GraphicsRect? = nil,
    clipPath: GraphicsPath? = nil,
    antialias: Bool = false,
    geometry: GraphicsShadingGeometry,
    mesh: GraphicsShadingMesh,
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous
  ) {
    self.init(
      type: type,
      colorSpace: colorSpace,
      colorRealization: colorRealization,
      background: background,
      bounds: bounds,
      clipPath: clipPath,
      antialias: antialias,
      geometry: geometry,
      mesh: mesh,
      sourcePatches: [],
      resourceIdentifier: resourceIdentifier
    )
  }

  /// Creates a semantic shading while retaining reconstructed patch source data.
  public init(
    type: Int,
    colorSpace: GraphicsColorSpaceDescription,
    colorRealization: GraphicsColorSpaceRealization? = nil,
    background: GraphicsPaint? = nil,
    bounds: GraphicsRect? = nil,
    clipPath: GraphicsPath? = nil,
    antialias: Bool = false,
    geometry: GraphicsShadingGeometry,
    mesh: GraphicsShadingMesh,
    sourcePatches: [GraphicsShadingPatch],
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous
  ) {
    self.resourceIdentifier = resourceIdentifier
    self.type = type
    self.colorSpace = colorSpace
    self.colorRealization = colorRealization
    self.background = background
    self.bounds = bounds
    self.clipPath = clipPath
    self.antialias = antialias
    self.geometry = geometry
    self.mesh = mesh
    self.sourcePatches = sourcePatches
  }
}
