import Foundation
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func generateAnnotationAppearance(
    _ annotation: PDFAnnotation,
    field: PDFFormField?,
    page: PDFPage
  ) async throws -> Bool {
    let location = PDFContentLocation(
      revision: resources.revision,
      pageIndex: page.index,
      pageReference: page.reference,
      decodedOffset: 0,
      segments: [],
      resourceStack: [annotation.identifier.reference]
    )
    if annotation.subtype == .widget {
      guard let field else { throw malformedGenerated("A widget has no resolved AcroForm field.", location) }
      guard field.type != .signature else {
        throw malformedGenerated("A signature widget requires an existing appearance.", location)
      }
      try resources.push(resources: field.resources)
      do {
        try await generateWidget(annotation, field: field, location: location)
        resources.pop()
        return true
      } catch {
        resources.pop()
        throw error
      }
    }
    switch annotation.subtype {
    case .sound, .movie, .screen, .threeD, .projection, .richMedia:
      return false
    default:
      try await generateStandardAnnotation(annotation, location: location)
      return true
    }
  }

  private func generateWidget(
    _ annotation: PDFAnnotation,
    field: PDFFormField,
    location: PDFContentLocation
  ) async throws {
    let rect = annotation.rectangle
    try await perform("q", [], location)
    try await perform("q", [], location)
    try await setGeneratedColor(annotation.rawDictionary["MK"], location: location)
    try await rectangle(rect, inset: 0, operation: "f", location: location)
    try await perform("Q", [], location)
    try await perform("G", [.real(0)], location)
    try await perform("w", [.real(borderWidth(annotation.rawDictionary))], location)
    try await rectangle(rect, inset: 0.5, operation: "S", location: location)

    switch field.type {
    case .button:
      if field.flags.contains(.pushButton) {
        if let label = field.alternateName ?? field.fullyQualifiedName {
          try await drawWidgetText(label, field: field, annotation: annotation, location: location)
        }
      } else if isButtonSelected(field.value) {
        try await drawCheckmark(in: rect, location: location)
      }
    case .text:
      if !field.flags.contains(.password), let value = stringValue(field.value) {
        try await drawWidgetText(value, field: field, annotation: annotation, location: location)
      } else if field.flags.contains(.password), let value = stringValue(field.value) {
        try await drawWidgetText(String(repeating: "•", count: value.count), field: field, annotation: annotation, location: location)
      }
    case .choice:
      let value = stringValue(field.value) ?? stringsValue(field.value).joined(separator: "\n")
      if !value.isEmpty { try await drawWidgetText(value, field: field, annotation: annotation, location: location) }
    case .signature:
      break
    case nil:
      throw malformedGenerated("A widget has no inherited field type.", location)
    }
    try await perform("Q", [], location)
  }

  private func generateStandardAnnotation(
    _ annotation: PDFAnnotation,
    location: PDFContentLocation
  ) async throws {
    let rect = annotation.rectangle
    let points = annotation.details.payload.points
    try await perform("q", [], location)
    try await annotationColor(annotation, location: location)
    try await perform("w", [.real(borderWidth(annotation.rawDictionary))], location)
    switch annotation.subtype {
    case .line where points.count >= 4:
      try await polyline(Array(points.prefix(4)), close: false, operation: "S", location: location)
    case .polygon where points.count >= 6:
      try await polyline(points, close: true, operation: "S", location: location)
    case .polyLine where points.count >= 4:
      try await polyline(points, close: false, operation: "S", location: location)
    case .highlight:
      try await annotationQuads(annotation, operation: "f", location: location)
    case .underline:
      try await annotationQuadLines(annotation, offset: 0, location: location)
    case .strikeOut:
      try await annotationQuadLines(annotation, offset: 0.5, location: location)
    case .squiggly:
      try await annotationSquiggles(annotation, location: location)
    case .ink:
      for path in annotation.details.payload.inkLists {
        try await polyline(path, close: false, operation: "S", location: location)
      }
    case .circle:
      try await ellipse(rect, location: location)
    case .square, .link, .freeText, .redact:
      try await rectangle(rect, inset: 0.5, operation: "S", location: location)
    case .text, .popup, .fileAttachment, .stamp, .caret:
      try await rectangle(rect, inset: 0.5, operation: "S", location: location)
      try await cross(rect, location: location)
    default:
      try await rectangle(rect, inset: 0.5, operation: "S", location: location)
    }
    try await perform("Q", [], location)
  }

  private func drawWidgetText(
    _ text: String,
    field: PDFFormField,
    annotation: PDFAnnotation,
    location: PDFContentLocation
  ) async throws {
    guard let appearance = field.defaultAppearance,
      let description = PDFVariableTextAppearanceSupport.style(from: appearance)
    else { throw malformedGenerated("Generated variable text requires a valid inherited DA.", location) }
    let fontSize = description.fontSize == 0 ? 12 : description.fontSize
    try await perform("BT", [], location)
    try await perform("Tf", [.name(description.fontName), .real(fontSize)], location)
    try await perform(
      description.colorOperator,
      description.colorComponents.map(PDFObject.real),
      location
    )
    let rect = annotation.rectangle
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let leading = fontSize * 1.2
    for (index, line) in lines.enumerated() {
      let x = rect.minimumX + 2
      let y = rect.maximumY - fontSize - 2 - Double(index) * leading
      try await perform("Tm", [.real(1), .real(0), .real(0), .real(1), .real(x), .real(y)], location)
      try await perform("Tj", [.string(.init(line))], location)
    }
    try await perform("ET", [], location)
  }

  private func annotationColor(_ annotation: PDFAnnotation, location: PDFContentLocation) async throws {
    guard case .array(let values)? = annotation.rawDictionary["C"] else {
      try await perform("G", [.real(0)], location)
      return
    }
    let components = try values.map(PDFObjectAccess.number)
    switch components.count {
    case 1: try await perform("G", components.map(PDFObject.real), location)
    case 3: try await perform("RG", components.map(PDFObject.real), location)
    case 4: try await perform("K", components.map(PDFObject.real), location)
    default: throw malformedGenerated("Annotation C has an invalid component count.", location)
    }
  }

  private func setGeneratedColor(_ appearance: PDFObject?, location: PDFContentLocation) async throws {
    guard case .dictionary(let dictionary)? = appearance,
      case .array(let values)? = dictionary["BG"]
    else {
      try await perform("g", [.real(1)], location)
      return
    }
    let components = try values.map(PDFObjectAccess.number)
    switch components.count {
    case 1: try await perform("g", components.map(PDFObject.real), location)
    case 3: try await perform("rg", components.map(PDFObject.real), location)
    case 4: try await perform("k", components.map(PDFObject.real), location)
    default: throw malformedGenerated("Widget MK BG has an invalid component count.", location)
    }
  }

  private func rectangle(
    _ rect: PDFRectangle,
    inset: Double,
    operation: String,
    location: PDFContentLocation
  ) async throws {
    try await perform("re", [
      .real(rect.minimumX + inset), .real(rect.minimumY + inset),
      .real(max(0, rect.maximumX - rect.minimumX - inset * 2)),
      .real(max(0, rect.maximumY - rect.minimumY - inset * 2)),
    ], location)
    try await perform(operation, [], location)
  }

  private func polyline(
    _ points: [Double],
    close: Bool,
    operation: String,
    location: PDFContentLocation
  ) async throws {
    guard points.count >= 4, points.count.isMultiple(of: 2) else {
      throw malformedGenerated("Generated annotation geometry has invalid point pairs.", location)
    }
    try await perform("m", [.real(points[0]), .real(points[1])], location)
    for index in stride(from: 2, to: points.count, by: 2) {
      try await perform("l", [.real(points[index]), .real(points[index + 1])], location)
    }
    if close { try await perform("h", [], location) }
    try await perform(operation, [], location)
  }

  private func annotationQuads(
    _ annotation: PDFAnnotation,
    operation: String,
    location: PDFContentLocation
  ) async throws {
    let values = annotation.details.payload.points
    guard values.count.isMultiple(of: 8) else { throw malformedGenerated("QuadPoints is malformed.", location) }
    for index in stride(from: 0, to: values.count, by: 8) {
      try await polyline(Array(values[index..<(index + 8)]), close: true, operation: operation, location: location)
    }
  }

  private func annotationQuadLines(
    _ annotation: PDFAnnotation,
    offset: Double,
    location: PDFContentLocation
  ) async throws {
    let values = annotation.details.payload.points
    guard values.count.isMultiple(of: 8) else { throw malformedGenerated("QuadPoints is malformed.", location) }
    for index in stride(from: 0, to: values.count, by: 8) {
      let y = values[index + 5] + (values[index + 1] - values[index + 5]) * offset
      try await polyline([values[index + 4], y, values[index + 6], y], close: false, operation: "S", location: location)
    }
  }

  private func annotationSquiggles(
    _ annotation: PDFAnnotation,
    location: PDFContentLocation
  ) async throws {
    let values = annotation.details.payload.points
    guard values.count.isMultiple(of: 8) else { throw malformedGenerated("QuadPoints is malformed.", location) }
    for index in stride(from: 0, to: values.count, by: 8) {
      let left = values[index + 4]
      let right = values[index + 6]
      let y = values[index + 5]
      let step = max(1, abs(values[index + 1] - y) / 3)
      var points = [left, y]
      var x = left + step
      var up = true
      while x < right {
        points.append(contentsOf: [x, y + (up ? step : 0)])
        up.toggle()
        x += step
      }
      points.append(contentsOf: [right, y])
      try await polyline(points, close: false, operation: "S", location: location)
    }
  }

  private func ellipse(_ rect: PDFRectangle, location: PDFContentLocation) async throws {
    let k = 0.552_284_749_830_793_6
    let rx = (rect.maximumX - rect.minimumX) / 2
    let ry = (rect.maximumY - rect.minimumY) / 2
    let cx = rect.minimumX + rx
    let cy = rect.minimumY + ry
    try await perform("m", [.real(cx + rx), .real(cy)], location)
    let curves = [
      [cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry],
      [cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy],
      [cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry],
      [cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy],
    ]
    for curve in curves { try await perform("c", curve.map(PDFObject.real), location) }
    try await perform("S", [], location)
  }

  private func cross(_ rect: PDFRectangle, location: PDFContentLocation) async throws {
    try await polyline(
      [rect.minimumX, rect.minimumY, rect.maximumX, rect.maximumY],
      close: false,
      operation: "S",
      location: location
    )
    try await polyline(
      [rect.minimumX, rect.maximumY, rect.maximumX, rect.minimumY],
      close: false,
      operation: "S",
      location: location
    )
  }

  private func drawCheckmark(in rect: PDFRectangle, location: PDFContentLocation) async throws {
    try await perform("w", [.real(max(1, (rect.maximumY - rect.minimumY) / 10))], location)
    try await polyline([
      rect.minimumX + (rect.maximumX - rect.minimumX) * 0.2,
      rect.minimumY + (rect.maximumY - rect.minimumY) * 0.5,
      rect.minimumX + (rect.maximumX - rect.minimumX) * 0.45,
      rect.minimumY + (rect.maximumY - rect.minimumY) * 0.25,
      rect.minimumX + (rect.maximumX - rect.minimumX) * 0.8,
      rect.minimumY + (rect.maximumY - rect.minimumY) * 0.8,
    ], close: false, operation: "S", location: location)
  }

  private func borderWidth(_ dictionary: [PDFName: PDFObject]) -> Double {
    if case .dictionary(let borderStyle)? = dictionary["BS"],
      let width = try? PDFObjectAccess.number(borderStyle["W"] ?? .integer(1))
    { return max(0, width) }
    if case .array(let border)? = dictionary["Border"], border.count >= 3,
      let width = try? PDFObjectAccess.number(border[2])
    { return max(0, width) }
    return 1
  }

  private func isButtonSelected(_ value: PDFFormValue?) -> Bool {
    guard case .name(let name)? = value else { return false }
    return name != PDFName("Off")
  }

  private func stringValue(_ value: PDFFormValue?) -> String? {
    guard case .string(let string)? = value else { return nil }
    return decodeText(string)
  }

  private func stringsValue(_ value: PDFFormValue?) -> [String] {
    guard case .strings(let strings)? = value else { return [] }
    return strings.map(decodeText)
  }

  private func decodeText(_ string: PDFString) -> String {
    if string.bytes.starts(with: [0xFE, 0xFF]) {
      let bytes = Array(string.bytes.dropFirst(2))
      let units = stride(from: 0, to: bytes.count - bytes.count % 2, by: 2).map {
        UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
      }
      return String(decoding: units, as: UTF16.self)
    }
    return String(data: string.bytes, encoding: .utf8)
      ?? String(decoding: string.bytes, as: Unicode.ASCII.self)
  }

  private func perform(
    _ name: String,
    _ operands: [PDFObject],
    _ location: PDFContentLocation
  ) async throws {
    try await execute(.init(operands: operands, name: name, location: location))
  }

  private func malformedGenerated(
    _ message: String,
    _ location: PDFContentLocation
  ) -> PDFGraphicsError {
    .malformedContent(message: message, operatorName: "generated-annotation-appearance", location: location)
  }
}
