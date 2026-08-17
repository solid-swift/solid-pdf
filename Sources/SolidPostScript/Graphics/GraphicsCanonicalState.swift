import Foundation

struct GraphicsCanonicalState: Sendable {
  var matrix: GraphicsMatrix
  var path: GraphicsPath
  var clip: GraphicsClip
  var paint: GraphicsPaint
  var lineWidth: Double
  var lineCap: GraphicsLineCap
  var lineJoin: GraphicsLineJoin
  var miterLimit: Double
  var dash: GraphicsDash
  var dashSource: Object?
  var clipStack: [GraphicsClip]

  static func initial(for descriptor: GraphicsDeviceDescriptor) -> Self {
    Self(
      matrix: descriptor.defaultMatrix,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: descriptor.imageableBounds),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash(),
      dashSource: nil,
      clipStack: []
    )
  }

  var snapshot: GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: matrix,
      path: path,
      clip: clip,
      paint: paint,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash
    )
  }

  func checkStorage(in vm: VM) throws {
    try dashSource?.checkStorage(in: vm)
  }
}

struct GraphicsStackFrame: Sendable {
  enum Kind: Sendable {
    case graphicsSave
    case languageSave(UInt64)
  }

  let kind: Kind
  let state: GraphicsCanonicalState
}
