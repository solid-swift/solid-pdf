import SolidPostScript

enum PDFPageAnalyzer {
  static func disposition(for effects: [GraphicsEffect]) -> PDFPageFallbackDisposition {
    effects.contains(where: requiresPageFallback) ? .page : .vector
  }

  private static func requiresPageFallback(_ effect: GraphicsEffect) -> Bool {
    let state: GraphicsStateSnapshot
    switch effect {
    case .fill(_, _, let value), .stroke(_, let value), .userPathFill(_, _, let value),
      .userPathStroke(_, let value), .erase(let value), .fillRectangles(_, let value),
      .strokeRectangles(_, _, let value), .image(_, let value), .shading(_, let value),
      .form(_, let value), .text(_, let value):
      state = value
    }
    guard state.deviceRendering == .continuousTone, !state.strokeAdjustment else { return true }
    if requiresPageFallback(state.paint) { return true }
    switch effect {
    case .form(let form, _):
      return form.displayList.effects.contains(where: requiresPageFallback)
    case .text(let run, _):
      return run.glyphs.contains { placement in
        switch placement.glyph.program {
        case .bitmap: true
        case .displayList(let list): list.effects.contains(where: requiresPageFallback)
        case .outline, .empty, .missing: false
        }
      }
    case .shading(let shading, _):
      return shading.mesh.triangles.contains { triangle in
        [triangle.first.paint, triangle.second.paint, triangle.third.paint]
          .contains(where: requiresPageFallback)
      }
    case .image(let image, _):
      if case .explicit(_, _, let maskToDevice, _) = image.descriptor.mask,
        maskToDevice != image.descriptor.imageToDevice
      { return true }
      return false
    default:
      return false
    }
  }

  private static func requiresPageFallback(_ paint: GraphicsPaint) -> Bool {
    switch paint {
    case .deviceGray, .deviceRGB, .deviceCMYK:
      false
    case .color(.deviceGray), .color(.deviceRGB), .color(.deviceCMYK):
      false
    case .color(.directColorants(_, let names, _)):
      names.count > 8
    case .color(.cie), .color(.named):
      true
    case .pattern(.empty):
      false
    case .pattern(.tiling(let pattern, let underlying)):
      (underlying.map(requiresPageFallback) ?? false)
        || pattern.displayList.effects.contains(where: requiresPageFallback)
    case .pattern(.shading(let shading)):
      shading.mesh.triangles.contains { triangle in
        [triangle.first.paint, triangle.second.paint, triangle.third.paint]
          .contains(where: requiresPageFallback)
      }
    }
  }
}
