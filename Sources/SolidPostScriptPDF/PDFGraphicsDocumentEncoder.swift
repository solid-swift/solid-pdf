import Foundation
import SolidPDF
import SolidPostScript
import SolidPostScriptRaster
import SolidRaster

enum PDFGraphicsDocumentEncoder {
  static func encode<Sink: PDFOutputSink>(
    plans: [PDFPagePlan],
    sink: Sink,
    options: PDFRenderOptions
  ) throws -> sending Sink.Session.Output {
    guard options.fallbackDPI.isFinite, options.fallbackDPI > 0 else {
      throw PDFError.invalidObject
    }
    var writer = try PDFDocumentWriter(
      sink: sink,
      options: PDFWritingOptions(
        version: options.version,
        compressionLevel: options.compressionLevel,
        limits: options.limits
      )
    )
    let catalog = try writer.reserveObject()
    let pagesRoot = try writer.reserveObject()
    let resourcesReference = try writer.reserveObject()
    let resources = PDFResourceManager<Sink>(resourcesReference: resourcesReference)
    var pageReferences: [PDFObjectReference] = []
    var pageDefinitions: [(reference: PDFObjectReference, contents: PDFObjectReference, plan: PDFPagePlan)] = []
    var diagnostics: [PDFDiagnostic] = []

    for plan in plans where plan.copies > 0 {
      let contentsReference = try writer.reserveObject()
      let disposition = PDFPageAnalyzer.disposition(for: plan.effects)
      let content: Data
      switch disposition {
      case .vector, .localized:
        content = try PDFGraphicsContentEncoder.encode(
          plan.effects,
          resources: resources,
          writer: &writer
        )
      case .page:
        guard options.fallbackPolicy == .exact else { throw PDFError.incompatibleVersion }
        let image = try rasterize(plan: plan, dpi: options.fallbackDPI)
        let name = try resources.ensureRasterImage(image, writer: &writer)
        var builder = PDFContentBuilder()
        let bounds = plan.device.descriptor.mediaBounds
        builder.command("q")
        builder.command(
          "\(builder.number(bounds.width)) 0 0 -\(builder.number(bounds.height)) "
            + "\(builder.number(bounds.x)) \(builder.number(bounds.maxY)) cm"
        )
        builder.command("/\(String(decoding: name.bytes, as: UTF8.self)) Do")
        builder.command("Q")
        content = builder.data
        diagnostics.append(PDFDiagnostic(
          kind: .rendering,
          message: "Rasterized output page \(pageReferences.count + 1) at \(options.fallbackDPI) dpi "
            + "because its effects depend on non-native rendering state."
        ))
      }
      try writer.writeStream(chunks: [content], to: contentsReference)
      for _ in 0..<plan.copies {
        let pageReference = try writer.reserveObject()
        pageReferences.append(pageReference)
        pageDefinitions.append((pageReference, contentsReference, plan))
      }
    }

    try resources.finish(writer: &writer)
    for definition in pageDefinitions {
      let bounds = definition.plan.device.descriptor.mediaBounds
      try writer.write(
        .dictionary([
          "Type": .name("Page"),
          "Parent": .reference(pagesRoot),
          "MediaBox": .array([
            .real(bounds.x), .real(bounds.y), .real(bounds.maxX), .real(bounds.maxY),
          ]),
          "Resources": .reference(resourcesReference),
          "Contents": .reference(definition.contents),
        ]),
        to: definition.reference
      )
    }
    try writer.write(
      .dictionary([
        "Type": .name("Pages"),
        "Count": .integer(pageReferences.count),
        "Kids": .array(pageReferences.map(PDFObject.reference)),
      ]),
      to: pagesRoot
    )
    try writer.write(
      .dictionary([
        "Type": .name("Catalog"),
        "Pages": .reference(pagesRoot),
      ]),
      to: catalog
    )
    let info = try makeInfo(options.metadata, writer: &writer)
    return try writer.finish(
      root: catalog,
      info: info,
      pageCount: pageReferences.count,
      diagnostics: diagnostics
    )
  }

  private static func rasterize(plan: PDFPagePlan, dpi: Double) throws -> RasterImage {
    let bounds = plan.device.descriptor.mediaBounds
    let scale = dpi / 72
    let width = Int((bounds.width * scale).rounded(.up))
    let height = Int((bounds.height * scale).rounded(.up))
    guard width > 0, height > 0 else { throw PDFError.limitExceeded }
    let target = RasterImageTarget(
      pixelWidth: width,
      pixelHeight: height,
      resolution: dpi,
      background: .white,
      pageDeviceMode: .fixed
    )
    let renderer = try target.makeRenderer()
    defer { renderer.abort() }
    return try renderer.renderCapturedPage(
      plan.effects,
      sourceDevice: plan.device.descriptor,
      scale: scale
    )
  }

  private static func makeInfo<Sink: PDFOutputSink>(
    _ metadata: PDFDocumentMetadata,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference? {
    var values: [PDFName: PDFObject] = [:]
    if let title = metadata.title { values["Title"] = .string(PDFString(title)) }
    if let creator = metadata.creator { values["Creator"] = .string(PDFString(creator)) }
    if let producer = metadata.producer { values["Producer"] = .string(PDFString(producer)) }
    if let creationDate = metadata.creationDate {
      values["CreationDate"] = .string(PDFString(dateString(creationDate)))
    }
    if let modificationDate = metadata.modificationDate {
      values["ModDate"] = .string(PDFString(dateString(modificationDate)))
    }
    guard !values.isEmpty else { return nil }
    let reference = try writer.reserveObject()
    try writer.write(.dictionary(values), to: reference)
    return reference
  }

  private static func dateString(_ date: Date) -> String {
    let components = Calendar(identifier: .gregorian).dateComponents(
      in: TimeZone(secondsFromGMT: 0)!,
      from: date
    )
    return String(
      format: "D:%04d%02d%02d%02d%02d%02dZ",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0,
      components.second ?? 0
    )
  }
}
