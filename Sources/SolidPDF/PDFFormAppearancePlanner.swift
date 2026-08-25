import Foundation

struct PDFFormAppearancePlanner<Session: PDFInputSourceSession> {
  let resolver: PDFDocumentResolver<Session>
  let form: PDFAcroForm
  let catalog: PDFDocumentCatalog
  let fields: [PDFFormFieldIdentifier: PDFFormField]
  let annotations: [PDFAnnotationIdentifier: PDFAnnotation]
  let transaction: PDFFormUpdateTransaction
  let revision: PDFDocumentRevision
  let base: PDFFormUpdatePlan
  let limits: PDFIncrementalWritingLimits

  func plan() async throws -> PDFFormUpdatePlan {
    var objects = base.objects
    var diagnostics = base.diagnostics
    var nextObjectNumber = max(
      Int(revision.trailer.pdfInteger(named: "Size") ?? 0),
      (objects.keys.map(\.objectNumber).max() ?? 0) + 1
    )
    var newReferences = [PDFObjectReference]()
    for update in transaction.updates {
      try Task.checkCancellation()
      guard let field = fields[update.field] else {
        throw PDFIncrementalUpdateError.unknownField(update.field)
      }
      for widget in field.widgets {
        guard let annotation = annotations[widget.annotationIdentifier] else {
          throw PDFIncrementalUpdateError.appearanceUnavailable(widget.annotationIdentifier)
        }
        var widgetDictionary = try dictionary(
          for: widget.annotationIdentifier.reference,
          fallback: widget.rawDictionary,
          in: objects
        )
        if field.type == .button {
          try generateButtonAppearance(
            field: field,
            update: update,
            annotation: annotation,
            widgetDictionary: &widgetDictionary,
            nextObjectNumber: &nextObjectNumber,
            objects: &objects,
            newReferences: &newReferences
          )
        } else {
          let display = try displayText(update, field: field)
          let generated = try await variableTextAppearance(
            display,
            field: field,
            annotation: annotation
          )
          let reference = PDFObjectReference(
            uncheckedObjectNumber: nextObjectNumber,
            generationNumber: 0
          )
          nextObjectNumber += 1
          objects[reference] = .stream(dictionary: generated.dictionary, bytes: generated.bytes)
          newReferences.append(reference)
          var appearances = appearanceDictionary(widgetDictionary["AP"])
          appearances["N"] = .reference(reference)
          widgetDictionary["AP"] = .dictionary(appearances)
        }
        objects[widget.annotationIdentifier.reference] = .value(.dictionary(widgetDictionary))
        diagnostics.append(.init(
          kind: .appearanceRegenerated,
          message: "Regenerated the appearance for widget \(widget.annotationIdentifier.reference.objectNumber)."
        ))
      }
    }
    try normalizeAcroForm(in: &objects)
    let changed = objects.keys.filter { !newReferences.contains($0) }.sorted()
    guard objects.count <= limits.maximumAppendedObjects else {
      throw PDFIncrementalUpdateError.limitExceeded
    }
    return PDFFormUpdatePlan(
      objects: objects,
      changedReferences: changed,
      newReferences: newReferences.sorted(),
      diagnostics: diagnostics
    )
  }

  private func variableTextAppearance(
    _ display: String,
    field: PDFFormField,
    annotation: PDFAnnotation
  ) async throws -> (dictionary: [PDFName: PDFObject], bytes: Data) {
    guard let defaultAppearance = field.defaultAppearance,
      let style = PDFVariableTextAppearanceSupport.style(from: defaultAppearance),
      let encoding = try await fontEncoding(named: style.fontName, resources: field.resources),
      let glyphBytes = PDFVariableTextAppearanceSupport.encodedGlyphBytes(display, encoding: encoding)
    else { throw PDFIncrementalUpdateError.unrepresentableText(field.identifier) }

    let width = max(0, annotation.rectangle.maximumX - annotation.rectangle.minimumX)
    let height = max(0, annotation.rectangle.maximumY - annotation.rectangle.minimumY)
    let size = style.fontSize == 0 ? max(4, min(12, height - 4)) : style.fontSize
    let text = try appearanceText(
      glyphBytes,
      display: display,
      style: style,
      encoding: encoding,
      size: size,
      width: width,
      height: height,
      field: field
    )
    let replacement = Data("/Tx BMC\n".utf8) + text + Data("EMC\n".utf8)
    var dictionary: [PDFName: PDFObject] = [
      "Type": .name("XObject"),
      "Subtype": .name("Form"),
      "FormType": .integer(1),
      "BBox": .array([.integer(0), .integer(0), .real(width), .real(height)]),
      "Resources": .dictionary(field.resources ?? [:]),
    ]
    var bytes = replacement
    if case .stream(let stream)? = annotation.appearances.normal {
      dictionary = stream.dictionary
      dictionary["Length"] = nil
      dictionary["Filter"] = nil
      dictionary["DecodeParms"] = nil
      let existing = try await resolver.decodedBytes(stream)
      bytes = replaceVariableText(in: existing, with: replacement)
      if dictionary["Resources"] == nil {
        dictionary["Resources"] = .dictionary(field.resources ?? [:])
      }
    } else if annotation.appearances.normal != nil {
      throw PDFIncrementalUpdateError.appearanceUnavailable(annotation.identifier)
    }
    guard bytes.count <= limits.maximumAppearanceStreamBytes else {
      throw PDFIncrementalUpdateError.limitExceeded
    }
    return (dictionary, bytes)
  }

  private func appearanceText(
    _ glyphBytes: Data,
    display: String,
    style: PDFVariableTextAppearanceStyle,
    encoding: PDFName,
    size: Double,
    width: Double,
    height: Double,
    field: PDFFormField
  ) throws -> Data {
    var result = Data("BT\n".utf8)
    var prefix = String(decoding: style.prefix, as: UTF8.self)
    if style.fontSize == 0 {
      prefix = prefix.replacingOccurrences(of: "/\(style.fontName.stringValue) 0 Tf", with: "/\(style.fontName.stringValue) \(number(size)) Tf")
    }
    result.append(Data(prefix.utf8))
    result.append(0x0A)
    let lines = field.flags.contains(.multiline)
      ? display.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      : [display.replacingOccurrences(of: "\n", with: " ")]
    let encodedLines: [Data]
    if field.flags.contains(.password) {
      encodedLines = lines.map { Data(repeating: 0x2A, count: $0.count) }
    } else if field.flags.contains(.comb), let maximum = field.maximumLength, maximum > 0 {
      encodedLines = [glyphBytes]
    } else {
      encodedLines = try lines.map { line in
        guard let data = PDFVariableTextAppearanceSupport.encodedGlyphBytes(line, encoding: encoding) else {
          throw PDFIncrementalUpdateError.unrepresentableText(field.identifier)
        }
        return data
      }
    }
    let leading = size * 1.2
    for (index, line) in encodedLines.enumerated() {
      let estimatedWidth = Double(line.count) * size * 0.5
      let x: Double
      switch field.justification {
      case 1: x = max(2, (width - estimatedWidth) / 2)
      case 2: x = max(2, width - estimatedWidth - 2)
      default: x = 2
      }
      let y = field.flags.contains(.multiline)
        ? max(2, height - size - 2 - Double(index) * leading)
        : max(2, (height - size) / 2)
      result.append(Data("1 0 0 1 \(number(x)) \(number(y)) Tm\n".utf8))
      result.append(try PDFObjectSerializer(limits: .init()).serialize(
        .string(PDFString(bytes: line, representation: .automatic))
      ))
      result.append(Data(" Tj\n".utf8))
    }
    result.append(Data("ET\n".utf8))
    return result
  }

  private func displayText(_ update: PDFFormFieldUpdate, field: PDFFormField) throws -> String {
    switch update.value {
    case .text(let value): return value
    case .encodedText(let value): return try PDFVariableTextAppearanceSupport.decodedText(value)
    case .choice(let values): return values.joined(separator: "\n")
    case .encodedChoice(let values):
      return try values.map(PDFVariableTextAppearanceSupport.decodedText).joined(separator: "\n")
    case .clear: return ""
    case .resetToDefault:
      return try text(from: field.defaultValue)
    case .button:
      return ""
    }
  }

  private func text(from value: PDFFormValue?) throws -> String {
    switch value {
    case .string(let string): return try PDFVariableTextAppearanceSupport.decodedText(string)
    case .strings(let strings):
      return try strings.map(PDFVariableTextAppearanceSupport.decodedText).joined(separator: "\n")
    case nil, .null: return ""
    default: throw PDFIncrementalUpdateError.validationFailed
    }
  }

  private func fontEncoding(
    named name: PDFName,
    resources: [PDFName: PDFObject]?
  ) async throws -> PDFName? {
    guard let resources,
      case .dictionary(let fonts)? = resources["Font"],
      let fontObject = fonts[name]
    else { return nil }
    let dictionary: [PDFName: PDFObject]
    if case .reference(let reference) = fontObject {
      let object = try await resolver.resolve(reference, in: revision.identifier)
      guard case .value(.dictionary(let value)) = object.value else { return nil }
      dictionary = value
    } else if case .dictionary(let value) = fontObject {
      dictionary = value
    } else { return nil }
    if let encoding = dictionary.pdfName(named: "Encoding") { return encoding }
    guard dictionary.pdfName(named: "Subtype") != "Type0" else { return nil }
    return "StandardEncoding"
  }

  private func generateButtonAppearance(
    field: PDFFormField,
    update: PDFFormFieldUpdate,
    annotation: PDFAnnotation,
    widgetDictionary: inout [PDFName: PDFObject],
    nextObjectNumber: inout Int,
    objects: inout [PDFObjectReference: PDFIncrementalObjectBody],
    newReferences: inout [PDFObjectReference]
  ) throws {
    let state: PDFName
    switch update.value {
    case .button(let value): state = value ?? "Off"
    case .clear: state = "Off"
    case .resetToDefault:
      if case .name(let value)? = field.defaultValue { state = value } else { state = "Off" }
    default:
      throw PDFIncrementalUpdateError.invalidFieldValue(field.identifier, reason: "A button requires a state.")
    }
    if case .states(let states)? = annotation.appearances.normal {
      guard states[state] != nil || state == PDFName("Off") && states["Off"] != nil else {
        throw PDFIncrementalUpdateError.appearanceUnavailable(annotation.identifier)
      }
      return
    }
    let width = max(0, annotation.rectangle.maximumX - annotation.rectangle.minimumX)
    let height = max(0, annotation.rectangle.maximumY - annotation.rectangle.minimumY)
    let off = PDFObjectReference(uncheckedObjectNumber: nextObjectNumber, generationNumber: 0)
    let on = PDFObjectReference(uncheckedObjectNumber: nextObjectNumber + 1, generationNumber: 0)
    nextObjectNumber += 2
    let dictionary: [PDFName: PDFObject] = [
      "Type": .name("XObject"), "Subtype": .name("Form"), "FormType": .integer(1),
      "BBox": .array([.integer(0), .integer(0), .real(width), .real(height)]),
      "Resources": .dictionary([:]),
    ]
    objects[off] = .stream(dictionary: dictionary, bytes: Data())
    objects[on] = .stream(
      dictionary: dictionary,
      bytes: Data("q 0 G 1 w 2 2 m \(number(width - 2)) \(number(height - 2)) l S 2 \(number(height - 2)) m \(number(width - 2)) 2 l S Q\n".utf8)
    )
    newReferences.append(contentsOf: [off, on])
    let onName = state == PDFName("Off") ? PDFName("Yes") : state
    widgetDictionary["AP"] = .dictionary([
      "N": .dictionary(["Off": .reference(off), onName: .reference(on)])
    ])
  }

  private func normalizeAcroForm(
    in objects: inout [PDFObjectReference: PDFIncrementalObjectBody]
  ) throws {
    var dictionary = form.rawDictionary
    dictionary["NeedAppearances"] = .boolean(false)
    if let reference = form.reference {
      objects[reference] = .value(.dictionary(dictionary))
    } else {
      var catalogDictionary = catalog.rawDictionary
      catalogDictionary["AcroForm"] = .dictionary(dictionary)
      objects[catalog.reference] = .value(.dictionary(catalogDictionary))
    }
  }

  private func dictionary(
    for reference: PDFObjectReference,
    fallback: [PDFName: PDFObject],
    in objects: [PDFObjectReference: PDFIncrementalObjectBody]
  ) throws -> [PDFName: PDFObject] {
    guard let body = objects[reference] else { return fallback }
    guard case .value(.dictionary(let dictionary)) = body else {
      throw PDFIncrementalUpdateError.validationFailed
    }
    return dictionary
  }

  private func appearanceDictionary(_ object: PDFObject?) -> [PDFName: PDFObject] {
    guard case .dictionary(let dictionary)? = object else { return [:] }
    return dictionary
  }

  private func replaceVariableText(in source: Data, with replacement: Data) -> Data {
    guard let start = source.range(of: Data("/Tx BMC".utf8)),
      let end = source.range(of: Data("EMC".utf8), in: start.upperBound..<source.endIndex)
    else {
      var result = source
      if result.last != 0x0A { result.append(0x0A) }
      result.append(replacement)
      return result
    }
    var result = source
    result.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
    return result
  }

  private func number(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(value)
  }
}

private extension PDFName {
  var stringValue: String { String(decoding: bytes, as: UTF8.self) }
}
