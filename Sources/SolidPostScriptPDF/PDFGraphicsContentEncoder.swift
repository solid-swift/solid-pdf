import Foundation
import SolidPDF
import SolidPostScript

enum PDFGraphicsContentEncoder {
  static func encode<Sink: PDFOutputSink>(
    _ effects: [GraphicsEffect],
    resources: PDFResourceManager<Sink>,
    writer: inout PDFDocumentWriter<Sink>,
    paintOverride: GraphicsPaint? = nil
  ) throws -> Data {
    var builder = PDFContentBuilder()
    for effect in effects {
      try append(
        effect,
        to: &builder,
        resources: resources,
        writer: &writer,
        paintOverride: paintOverride
      )
    }
    return builder.data
  }

  private static func append<Sink: PDFOutputSink>(
    _ effect: GraphicsEffect,
    to builder: inout PDFContentBuilder,
    resources: PDFResourceManager<Sink>,
    writer: inout PDFDocumentWriter<Sink>,
    paintOverride: GraphicsPaint?
  ) throws {
    switch effect {
    case .erase(let state):
      builder.command("q")
      builder.command("1 g")
      builder.rectangle(state.device.descriptor.mediaBounds)
      builder.command("f")
      builder.command("Q")
    case .fill(let path, let rule, let state), .userPathFill(let path, let rule, let state):
      guard !isEmptyPattern(state.paint, override: paintOverride) else { return }
      try begin(
        state,
        in: &builder,
        resources: resources,
        writer: &writer,
        stroking: false,
        paintOverride: paintOverride
      )
      builder.path(path)
      builder.command(rule == .evenOdd ? "f*" : "f")
      builder.command("Q")
    case .userPathStroke(let outline, let state):
      guard !isEmptyPattern(state.paint, override: paintOverride) else { return }
      try begin(
        state,
        in: &builder,
        resources: resources,
        writer: &writer,
        stroking: false,
        paintOverride: paintOverride
      )
      builder.path(outline)
      builder.command("f")
      builder.command("Q")
    case .stroke(let path, let state):
      try stroke(
        path,
        state: state,
        matrix: state.matrix,
        builder: &builder,
        resources: resources,
        writer: &writer,
        paintOverride: paintOverride
      )
    case .fillRectangles(let paths, let state):
      guard !isEmptyPattern(state.paint, override: paintOverride) else { return }
      try begin(
        state,
        in: &builder,
        resources: resources,
        writer: &writer,
        stroking: false,
        paintOverride: paintOverride
      )
      for path in paths { builder.path(path) }
      builder.command("f")
      builder.command("Q")
    case .strokeRectangles(let paths, let matrix, let state):
      let path = GraphicsPath(elements: paths.flatMap(\.elements))
      try stroke(
        path,
        state: state,
        matrix: matrix?.concatenated(with: state.matrix) ?? state.matrix,
        builder: &builder,
        resources: resources,
        writer: &writer,
        paintOverride: paintOverride
      )
    case .image(let image, let state):
      try beginClip(state, in: &builder)
      guard !isEmptyPattern(state.paint, override: paintOverride) else { return }
      try appendPaint(
        state,
        stroking: false,
        to: &builder,
        resources: resources,
        writer: &writer,
        paintOverride: paintOverride
      )
      let name = try resources.ensureImage(image, writer: &writer)
      let descriptor = image.descriptor
      let imageMatrix = GraphicsMatrix(
        a: Double(descriptor.width), b: 0, c: 0, d: -Double(descriptor.height),
        tx: 0, ty: Double(descriptor.height)
      ).concatenated(with: descriptor.imageToDevice)
      builder.command("\(builder.matrix(imageMatrix)) cm")
      builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) Do")
      builder.command("Q")
    case .shading(let shading, let state):
      try beginClip(state, in: &builder)
      let name = try resources.ensureShading(shading, writer: &writer)
      builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) sh")
      builder.command("Q")
    case .form(let form, let state):
      try beginClip(state, in: &builder)
      let name = try resources.ensureForm(form, writer: &writer)
      builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) Do")
      builder.command("Q")
    case .text(let run, let state):
      for placement in run.glyphs {
        switch placement.glyph.program {
        case .outline(let path):
          guard !isEmptyPattern(state.paint, override: paintOverride) else { continue }
          let font = placement.font ?? run.rootFont
          if let selection = resources.fontSelection(font: font, glyph: placement.glyph) {
            try begin(
              state,
              in: &builder,
              resources: resources,
              writer: &writer,
              stroking: false,
              paintOverride: paintOverride
            )
            builder.command("BT")
            builder.command(
              "/\(String(decoding: selection.name.bytes, as: UTF8.self)) "
                + "\(builder.number(selection.size)) Tf"
            )
            builder.command("\(builder.matrix(placement.transform)) Tm")
            builder.command("<\(selection.code.map { String(format: "%02X", $0) }.joined())> Tj")
            builder.command("ET")
            builder.command("Q")
            continue
          }
          try begin(
            state,
            in: &builder,
            resources: resources,
            writer: &writer,
            stroking: false,
            paintOverride: paintOverride
          )
          builder.path(path, transformedBy: placement.transform)
          builder.command("f")
          builder.command("Q")
        case .displayList(let list):
          for nested in list.effects {
            try append(
              nested,
              to: &builder,
              resources: resources,
              writer: &writer,
              paintOverride: paintOverride
            )
          }
        case .empty, .missing:
          let font = placement.font ?? run.rootFont
          guard let selection = resources.fontSelection(font: font, glyph: placement.glyph) else { continue }
          try beginClip(state, in: &builder)
          builder.command("BT")
          builder.command(
            "/\(String(decoding: selection.name.bytes, as: UTF8.self)) "
              + "\(builder.number(selection.size)) Tf"
          )
          builder.command("\(builder.matrix(placement.transform)) Tm")
          builder.command("<\(selection.code.map { String(format: "%02X", $0) }.joined())> Tj")
          builder.command("ET")
          builder.command("Q")
        case .bitmap:
          break
        }
      }
    }
  }

  private static func stroke<Sink: PDFOutputSink>(
    _ path: GraphicsPath,
    state: GraphicsStateSnapshot,
    matrix: GraphicsMatrix,
    builder: inout PDFContentBuilder,
    resources: PDFResourceManager<Sink>,
    writer: inout PDFDocumentWriter<Sink>,
    paintOverride: GraphicsPaint?
  ) throws {
    guard let inverse = matrix.inverted else { return }
    try beginClip(state, in: &builder)
    guard !isEmptyPattern(state.paint, override: paintOverride) else {
      builder.command("Q")
      return
    }
    try appendPaint(
      state,
      stroking: true,
      to: &builder,
      resources: resources,
      writer: &writer,
      paintOverride: paintOverride
    )
    builder.command("\(builder.matrix(matrix)) cm")
    builder.command("\(builder.number(state.lineWidth)) w")
    builder.command("\(state.lineCap.rawValue) J")
    builder.command("\(state.lineJoin.rawValue) j")
    builder.command("\(builder.number(state.miterLimit)) M")
    let dash = state.dash.pattern.map(builder.number).joined(separator: " ")
    builder.command("[\(dash)] \(builder.number(state.dash.phase)) d")
    builder.path(path, transformedBy: inverse)
    builder.command("S")
    builder.command("Q")
  }

  private static func begin<Sink: PDFOutputSink>(
    _ state: GraphicsStateSnapshot,
    in builder: inout PDFContentBuilder,
    resources: PDFResourceManager<Sink>,
    writer: inout PDFDocumentWriter<Sink>,
    stroking: Bool,
    paintOverride: GraphicsPaint?
  ) throws {
    try beginClip(state, in: &builder)
    try appendPaint(
      state,
      stroking: stroking,
      to: &builder,
      resources: resources,
      writer: &writer,
      paintOverride: paintOverride
    )
  }

  private static func beginClip(_ state: GraphicsStateSnapshot, in builder: inout PDFContentBuilder) throws {
    builder.command("q")
    builder.rectangle(state.clip.imageableBounds)
    builder.command("W n")
    for constraint in state.clip.constraints {
      builder.path(constraint.path)
      builder.command(constraint.rule == .evenOdd ? "W* n" : "W n")
    }
  }

  private static func appendPaint<Sink: PDFOutputSink>(
    _ state: GraphicsStateSnapshot,
    stroking: Bool,
    to builder: inout PDFContentBuilder,
    resources: PDFResourceManager<Sink>,
    writer: inout PDFDocumentWriter<Sink>,
    paintOverride: GraphicsPaint?
  ) throws {
    let overprint = try resources.ensureOverprint(state.overprint, writer: &writer)
    builder.command("/\(String(decoding: overprint.bytes, as: UTF8.self)) gs")
    let suffix = stroking ? "" : "g"
    let rgbSuffix = stroking ? "RG" : "rg"
    let cmykSuffix = stroking ? "K" : "k"
    switch paintOverride ?? state.paint {
    case .deviceGray(let gray), .color(.deviceGray(let gray)):
      builder.command("\(builder.number(gray)) \(stroking ? "G" : suffix)")
    case .deviceRGB(let red, let green, let blue):
      builder.command("\(builder.number(red)) \(builder.number(green)) \(builder.number(blue)) \(rgbSuffix)")
    case .color(.deviceRGB(let rgb)):
      builder.command(
        "\(builder.number(rgb.red)) \(builder.number(rgb.green)) \(builder.number(rgb.blue)) \(rgbSuffix)"
      )
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      builder.command(
        "\(builder.number(cyan)) \(builder.number(magenta)) \(builder.number(yellow)) "
          + "\(builder.number(black)) \(cmykSuffix)"
      )
    case .color(.deviceCMYK(let cmyk)):
      builder.command(
        "\(builder.number(cmyk.cyan)) \(builder.number(cmyk.magenta)) \(builder.number(cmyk.yellow)) "
          + "\(builder.number(cmyk.black)) \(cmykSuffix)"
      )
    case .color(.directColorants(let space, _, let tints)):
      let name = try resources.ensureColorSpace(space, writer: &writer)
      builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) \(stroking ? "CS" : "cs")")
      let values = tints.map(builder.number).joined(separator: " ")
      builder.command("\(values) \(stroking ? "SCN" : "scn")")
    case .color(let color):
      let rgb = color.rgb
      builder.command(
        "\(builder.number(rgb.red)) \(builder.number(rgb.green)) \(builder.number(rgb.blue)) \(rgbSuffix)"
      )
    case .pattern(let pattern):
      guard pattern != .empty else { return }
      let name = try resources.ensurePattern(pattern, writer: &writer)
      builder.command("/Pattern \(stroking ? "CS" : "cs")")
      builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) \(stroking ? "SCN" : "scn")")
    }
  }

  private static func isEmptyPattern(_ paint: GraphicsPaint, override: GraphicsPaint?) -> Bool {
    if case .pattern(.empty) = override ?? paint { true } else { false }
  }
}
