import Foundation
import SolidPDF
import SolidPostScript
import SolidRaster

final class PDFResourceManager<Sink: PDFOutputSink> {
  private struct NamedReference {
    let name: PDFName
    let reference: PDFObjectReference
  }

  private struct GlyphFontKey: Hashable {
    let font: GraphicsFontIdentifier
    let glyph: GraphicsGlyphDescription
  }

  private var images: [GraphicsImage: NamedReference] = [:]
  private var rasterImages: [RasterImage: NamedReference] = [:]
  private var forms: [GraphicsForm: NamedReference] = [:]
  private var patterns: [GraphicsPatternPaint: NamedReference] = [:]
  private var shadings: [GraphicsShading: NamedReference] = [:]
  private var colorSpaces: [GraphicsColorSpaceDescription: NamedReference] = [:]
  private var overprintStates: [Bool: NamedReference] = [:]
  private var glyphFonts: [GlyphFontKey: NamedReference] = [:]
  private var xObjects: [PDFName: PDFObjectReference] = [:]
  private var shadingObjects: [PDFName: PDFObjectReference] = [:]
  private var patternObjects: [PDFName: PDFObjectReference] = [:]
  private var colorSpaceObjects: [PDFName: PDFObjectReference] = [:]
  private var graphicsStates: [PDFName: PDFObjectReference] = [:]
  private var fontObjects: [PDFName: PDFObjectReference] = [:]
  private let resourcesReference: PDFObjectReference

  init(resourcesReference: PDFObjectReference) {
    self.resourcesReference = resourcesReference
  }

  func finish(writer: inout PDFDocumentWriter<Sink>) throws {
    var resources: [PDFName: PDFObject] = [:]
    if !xObjects.isEmpty {
      resources["XObject"] = .dictionary(xObjects.mapValues(PDFObject.reference))
    }
    if !shadingObjects.isEmpty {
      resources["Shading"] = .dictionary(shadingObjects.mapValues(PDFObject.reference))
    }
    if !patternObjects.isEmpty {
      resources["Pattern"] = .dictionary(patternObjects.mapValues(PDFObject.reference))
    }
    if !colorSpaceObjects.isEmpty {
      resources["ColorSpace"] = .dictionary(colorSpaceObjects.mapValues(PDFObject.reference))
    }
    if !graphicsStates.isEmpty {
      resources["ExtGState"] = .dictionary(graphicsStates.mapValues(PDFObject.reference))
    }
    if !fontObjects.isEmpty {
      resources["Font"] = .dictionary(fontObjects.mapValues(PDFObject.reference))
    }
    try writer.write(.dictionary(resources), to: resourcesReference)
  }

  func ensureGlyphFont(
    font: GraphicsFontDescription,
    glyph: GraphicsGlyphDescription,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName? {
    switch glyph.program {
    case .outline, .empty, .missing: break
    case .bitmap, .displayList: return nil
    }
    let key = GlyphFontKey(font: font.identifier, glyph: glyph)
    if let existing = glyphFonts[key] { return existing.name }
    let name = PDFName("F\(glyphFonts.count + 1)")
    let fontReference = try writer.reserveObject()
    let characterReference = try writer.reserveObject()
    let characterName = PDFName("g")
    glyphFonts[key] = NamedReference(name: name, reference: fontReference)
    fontObjects[name] = fontReference

    let bounds = glyph.metrics.bounds ?? pathBounds(glyph.program)
    var character = PDFContentBuilder()
    character.command(
      "\(character.number(glyph.metrics.horizontalAdvance.x)) "
        + "\(character.number(glyph.metrics.horizontalAdvance.y)) "
        + "\(character.number(bounds.x)) \(character.number(bounds.y)) "
        + "\(character.number(bounds.maxX)) \(character.number(bounds.maxY)) d1"
    )
    if case .outline(let path) = glyph.program {
      character.path(path)
      character.command("f")
    }
    try writer.writeStream(chunks: [character.data], to: characterReference)

    let baseName = font.postScriptName ?? font.resourceName ?? "SolidGlyph"
    try writer.write(
      .dictionary([
        "Type": .name("Font"),
        "Subtype": .name("Type3"),
        "Name": .name(PDFName(baseName)),
        "FontBBox": .array([
          .real(bounds.x), .real(bounds.y), .real(bounds.maxX), .real(bounds.maxY),
        ]),
        "FontMatrix": .array([
          .integer(1), .integer(0), .integer(0), .integer(1), .integer(0), .integer(0),
        ]),
        "CharProcs": .dictionary([characterName: .reference(characterReference)]),
        "Encoding": .dictionary([
          "Type": .name("Encoding"),
          "Differences": .array([.integer(0), .name(characterName)]),
        ]),
        "FirstChar": .integer(0),
        "LastChar": .integer(0),
        "Widths": .array([.real(glyph.metrics.horizontalAdvance.x)]),
        "Resources": .reference(resourcesReference),
      ]),
      to: fontReference
    )
    return name
  }

  func ensureImage(
    _ image: GraphicsImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = images[image] { return existing.name }
    let name = PDFName("Im\(images.count + rasterImages.count + 1)")
    let reference = try writer.reserveObject()
    images[image] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    let mask = try makeMask(for: image, writer: &writer)
    let bits = image.descriptor.sourceBitsPerComponent > 8 ? 16 : 8
    let components = image.descriptor.kind.componentCount
    var bytes = Data()
    bytes.reserveCapacity(image.descriptor.width * image.descriptor.height * components * (bits / 8))
    let expected = image.descriptor.width * image.descriptor.height * components
    for index in 0..<expected {
      let value = index < image.components.count ? min(1, max(0, image.components[index])) : 0
      if bits == 16 {
        let sample = UInt16((value * Float(UInt16.max)).rounded())
        bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        bytes.append(UInt8(truncatingIfNeeded: sample))
      } else {
        bytes.append(UInt8((value * 255).rounded()))
      }
    }
    var dictionary: [PDFName: PDFObject] = [
      "Type": .name("XObject"),
      "Subtype": .name("Image"),
      "Width": .integer(image.descriptor.width),
      "Height": .integer(image.descriptor.height),
      "BitsPerComponent": .integer(bits),
    ]
    switch image.descriptor.kind {
    case .color(.deviceGray): dictionary["ColorSpace"] = .name("DeviceGray")
    case .color(.deviceRGB): dictionary["ColorSpace"] = .name("DeviceRGB")
    case .color(.deviceCMYK): dictionary["ColorSpace"] = .name("DeviceCMYK")
    case .mask:
      dictionary["ImageMask"] = .boolean(true)
      dictionary["Decode"] = .array([.integer(0), .integer(1)])
    }
    if let mask { dictionary["SMask"] = .reference(mask) }
    try writer.writeStream(dictionary: dictionary, chunks: [bytes], to: reference)
    return name
  }

  func ensureRasterImage(
    _ image: RasterImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = rasterImages[image] { return existing.name }
    let name = PDFName("Im\(images.count + rasterImages.count + 1)")
    let reference = try writer.reserveObject()
    let maskReference = try writer.reserveObject()
    rasterImages[image] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    var rgb = Data()
    var alpha = Data()
    rgb.reserveCapacity(image.width * image.height * 3)
    alpha.reserveCapacity(image.width * image.height)
    for row in 0..<image.height {
      for column in 0..<image.width {
        let offset = row * image.bytesPerRow + column * 4
        let opacity = image.data[offset + 3]
        let components = [image.data[offset], image.data[offset + 1], image.data[offset + 2]]
        for component in components {
          if image.pixelFormat == .rgba8UnormPremultiplied, opacity != 0 {
            rgb.append(UInt8(clamping: (Int(component) * 255 + Int(opacity) / 2) / Int(opacity)))
          } else {
            rgb.append(component)
          }
        }
        alpha.append(opacity)
      }
    }
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(image.width), "Height": .integer(image.height),
        "ColorSpace": .name("DeviceGray"), "BitsPerComponent": .integer(8),
      ],
      chunks: [alpha],
      to: maskReference
    )
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(image.width), "Height": .integer(image.height),
        "ColorSpace": .name("DeviceRGB"), "BitsPerComponent": .integer(8),
        "SMask": .reference(maskReference),
      ],
      chunks: [rgb],
      to: reference
    )
    return name
  }

  func ensureForm(
    _ form: GraphicsForm,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = forms[form] { return existing.name }
    let name = PDFName("Fm\(forms.count + 1)")
    let reference = try writer.reserveObject()
    forms[form] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    let content = try PDFGraphicsContentEncoder.encode(
      form.displayList.effects,
      resources: self,
      writer: &writer
    )
    let bounds = form.bounds
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"),
        "Subtype": .name("Form"),
        "FormType": .integer(1),
        "BBox": .array([
          .real(bounds.x), .real(bounds.y), .real(bounds.maxX), .real(bounds.maxY),
        ]),
        "Resources": .reference(resourcesReference),
      ],
      chunks: [content],
      to: reference
    )
    return name
  }

  func ensureShading(
    _ shading: GraphicsShading,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = shadings[shading] { return existing.name }
    let name = PDFName("Sh\(shadings.count + 1)")
    let reference = try writer.reserveObject()
    shadings[shading] = NamedReference(name: name, reference: reference)
    shadingObjects[name] = reference
    let triangles = shading.mesh.triangles
    let points = triangles.flatMap { [$0.first.position, $0.second.position, $0.third.position] }
    let minimumX = points.map(\.x).min() ?? 0
    let maximumX = points.map(\.x).max() ?? minimumX + 1
    let minimumY = points.map(\.y).min() ?? 0
    let maximumY = points.map(\.y).max() ?? minimumY + 1
    let width = max(Double.leastNonzeroMagnitude, maximumX - minimumX)
    let height = max(Double.leastNonzeroMagnitude, maximumY - minimumY)
    var data = Data()
    for triangle in triangles {
      for vertex in [triangle.first, triangle.second, triangle.third] {
        data.append(0)
        data.appendBigEndian(UInt32(((vertex.position.x - minimumX) / width * Double(UInt32.max)).rounded()))
        data.appendBigEndian(UInt32(((vertex.position.y - minimumY) / height * Double(UInt32.max)).rounded()))
        let rgb = vertex.paint.rgbComponents
        data.append(UInt8((min(1, max(0, rgb.red)) * 255).rounded()))
        data.append(UInt8((min(1, max(0, rgb.green)) * 255).rounded()))
        data.append(UInt8((min(1, max(0, rgb.blue)) * 255).rounded()))
      }
    }
    try writer.writeStream(
      dictionary: [
        "ShadingType": .integer(4),
        "ColorSpace": .name("DeviceRGB"),
        "BitsPerCoordinate": .integer(32),
        "BitsPerComponent": .integer(8),
        "BitsPerFlag": .integer(8),
        "Decode": .array([
          .real(minimumX), .real(maximumX), .real(minimumY), .real(maximumY),
          .integer(0), .integer(1), .integer(0), .integer(1), .integer(0), .integer(1),
        ]),
      ],
      chunks: [data],
      to: reference
    )
    return name
  }

  func ensurePattern(
    _ paint: GraphicsPatternPaint,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = patterns[paint] { return existing.name }
    let name = PDFName("P\(patterns.count + 1)")
    let reference = try writer.reserveObject()
    patterns[paint] = NamedReference(name: name, reference: reference)
    patternObjects[name] = reference
    switch paint {
    case .empty:
      try writer.write(.dictionary(["PatternType": .integer(1)]), to: reference)
    case .shading(let shading):
      let shadingName = try ensureShading(shading, writer: &writer)
      guard let shadingReference = shadingObjects[shadingName] else { throw PDFError.invalidReference }
      try writer.write(
        .dictionary([
          "Type": .name("Pattern"),
          "PatternType": .integer(2),
          "Shading": .reference(shadingReference),
        ]),
        to: reference
      )
    case .tiling(let pattern, let underlying):
      guard let inverse = pattern.matrix.inverted else { throw PDFError.invalidObject }
      var content = PDFContentBuilder()
      content.command("q")
      content.command("\(content.matrix(inverse)) cm")
      content.append(try PDFGraphicsContentEncoder.encode(
        pattern.displayList.effects,
        resources: self,
        writer: &writer,
        paintOverride: underlying
      ))
      content.command("Q")
      try writer.writeStream(
        dictionary: [
          "Type": .name("Pattern"),
          "PatternType": .integer(1),
          "PaintType": .integer(1),
          "TilingType": .integer(pattern.tilingType),
          "BBox": .array([
            .real(pattern.bounds.x), .real(pattern.bounds.y),
            .real(pattern.bounds.maxX), .real(pattern.bounds.maxY),
          ]),
          "XStep": .real(pattern.xStep),
          "YStep": .real(pattern.yStep),
          "Matrix": .array([
            .real(pattern.matrix.a), .real(pattern.matrix.b),
            .real(pattern.matrix.c), .real(pattern.matrix.d),
            .real(pattern.matrix.tx), .real(pattern.matrix.ty),
          ]),
          "Resources": .reference(resourcesReference),
        ],
        chunks: [content.data],
        to: reference
      )
    }
    return name
  }

  func ensureColorSpace(
    _ space: GraphicsColorSpaceDescription,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = colorSpaces[space] { return existing.name }
    let name = PDFName("Cs\(colorSpaces.count + 1)")
    let reference = try writer.reserveObject()
    colorSpaces[space] = NamedReference(name: name, reference: reference)
    colorSpaceObjects[name] = reference
    switch space {
    case .separation(let colorant, _):
      let function = try makeTintFunction(componentCount: 1, writer: &writer)
      try writer.write(
        .array([
          .name("Separation"), .name(PDFName(colorant)), .name("DeviceCMYK"), .reference(function),
        ]),
        to: reference
      )
    case .deviceN(let colorants, _):
      let function = try makeTintFunction(componentCount: colorants.count, writer: &writer)
      try writer.write(
        .array([
          .name("DeviceN"), .array(colorants.map { .name(PDFName($0)) }),
          .name("DeviceCMYK"), .reference(function),
        ]),
        to: reference
      )
    default:
      throw PDFError.invalidObject
    }
    return name
  }

  func ensureOverprint(
    _ enabled: Bool,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = overprintStates[enabled] { return existing.name }
    let name = PDFName(enabled ? "GSop" : "GSko")
    let reference = try writer.reserveObject()
    overprintStates[enabled] = NamedReference(name: name, reference: reference)
    graphicsStates[name] = reference
    try writer.write(
      .dictionary([
        "Type": .name("ExtGState"),
        "OP": .boolean(enabled),
        "op": .boolean(enabled),
        "OPM": .integer(1),
      ]),
      to: reference
    )
    return name
  }

  private func makeMask(
    for image: GraphicsImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference? {
    let width: Int
    let height: Int
    var opacities: [Float]
    if let mask = image.mask {
      switch mask.descriptor {
      case .explicit(let maskWidth, let maskHeight, _, _):
        width = maskWidth; height = maskHeight
      case .colorKey:
        width = image.descriptor.width; height = image.descriptor.height
      }
      opacities = mask.opacities
    } else if image.completedRowCount < image.descriptor.height {
      width = image.descriptor.width; height = image.descriptor.height
      opacities = [Float](
        repeating: 1,
        count: image.completedRowCount * image.descriptor.width
      )
    } else {
      return nil
    }
    let total = width * height
    if opacities.count < total { opacities.append(contentsOf: repeatElement(0, count: total - opacities.count)) }
    let data = Data(opacities.prefix(total).map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
    let reference = try writer.reserveObject()
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(width), "Height": .integer(height),
        "ColorSpace": .name("DeviceGray"), "BitsPerComponent": .integer(8),
      ],
      chunks: [data],
      to: reference
    )
    return reference
  }

  private func makeTintFunction(
    componentCount: Int,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference {
    guard (1...8).contains(componentCount) else { throw PDFError.limitExceeded }
    let reference = try writer.reserveObject()
    let sampleCount = 1 << componentCount
    var samples = Data()
    for sample in 0..<sampleCount {
      var maximum = 0
      for bit in 0..<componentCount where sample & (1 << bit) != 0 { maximum = 255 }
      samples.append(contentsOf: [0, 0, 0, UInt8(maximum)])
    }
    try writer.writeStream(
      dictionary: [
        "FunctionType": .integer(0),
        "Domain": .array((0..<componentCount).flatMap { _ in [.integer(0), .integer(1)] }),
        "Range": .array((0..<4).flatMap { _ in [.integer(0), .integer(1)] }),
        "Size": .array((0..<componentCount).map { _ in .integer(2) }),
        "BitsPerSample": .integer(8),
      ],
      chunks: [samples],
      to: reference
    )
    return reference
  }

  private func pathBounds(_ program: GraphicsGlyphProgram) -> GraphicsRect {
    guard case .outline(let path) = program else { return .init(x: 0, y: 0, width: 0, height: 0) }
    let points = path.elements.flatMap { element -> [GraphicsPoint] in
      switch element {
      case .move(let point), .line(let point): [point]
      case .curve(let first, let second, let end): [first, second, end]
      case .close: []
      }
    }
    guard let minimumX = points.map(\.x).min(), let maximumX = points.map(\.x).max(),
      let minimumY = points.map(\.y).min(), let maximumY = points.map(\.y).max()
    else { return .init(x: 0, y: 0, width: 0, height: 0) }
    return GraphicsRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
  }
}

private extension Data {
  mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [
      UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
    ])
  }
}
