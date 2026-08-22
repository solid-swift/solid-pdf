import SolidPostScript

enum PDFPageAnalyzer {
  enum EffectDisposition: Equatable { case vector, localized, page }

  static func disposition(for effects: [GraphicsEffect]) -> PDFPageFallbackDisposition {
    let dispositions = effects.map(disposition)
    if dispositions.contains(where: { $0 == .page }) { return .page }
    if dispositions.contains(where: { $0 == .localized }) { return .localized }
    return .vector
  }

  static func disposition(for effect: GraphicsEffect) -> EffectDisposition {
    let state: GraphicsStateSnapshot
    switch effect {
    case .fill(_, _, let value), .stroke(_, let value), .userPathFill(_, _, let value),
      .userPathStroke(_, let value), .erase(let value), .fillRectangles(_, let value),
      .strokeRectangles(_, _, let value), .image(_, let value), .shading(_, let value),
      .form(_, let value), .text(_, let value), .markedContent(_, let value):
      state = value
    }
    let unsupportedState = state.deviceRendering != .continuousTone || state.strokeAdjustment
      || requiresFallback(state.paint)
    if unsupportedState { return state.overprint || addressesNamedColorants(state.paint) ? .page : .localized }
    switch effect {
    case .form(let form, _):
      let nested = disposition(for: form.displayList.effects)
      return nested == .vector ? .vector : (state.overprint ? .page : .localized)
    case .text(let run, _):
      let unsupported = run.glyphs.contains { placement in
        switch placement.glyph.program {
        case .bitmap: true
        case .displayList(let list): disposition(for: list.effects) != .vector
        case .outline, .empty, .missing: false
        }
      }
      return unsupported ? (state.overprint ? .page : .localized) : .vector
    case .shading(let shading, _):
      let unsupported = shading.mesh.triangles.contains { triangle in
        [triangle.first.paint, triangle.second.paint, triangle.third.paint]
          .contains(where: requiresFallback)
      }
      return unsupported ? (state.overprint ? .page : .localized) : .vector
    case .image(let image, _):
      if case .explicit(_, _, let maskToDevice, _) = image.descriptor.mask,
        maskToDevice != image.descriptor.imageToDevice
      { return state.overprint ? .page : .localized }
      return .vector
    default:
      return .vector
    }
  }

  private static func requiresFallback(_ paint: GraphicsPaint) -> Bool {
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
      (underlying.map(requiresFallback) ?? false)
        || disposition(for: pattern.displayList.effects) != .vector
    case .pattern(.shading(let shading)):
      shading.mesh.triangles.contains { triangle in
        [triangle.first.paint, triangle.second.paint, triangle.third.paint]
          .contains(where: requiresFallback)
      }
    }
  }

  private static func addressesNamedColorants(_ paint: GraphicsPaint) -> Bool {
    if case .color(.directColorants) = paint { true } else { false }
  }
}
