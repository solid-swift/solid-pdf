import Foundation

struct PDFFormUpdatePlan: Sendable {
  let objects: [PDFObjectReference: PDFIncrementalObjectBody]
  let changedReferences: [PDFObjectReference]
  let newReferences: [PDFObjectReference]
  let diagnostics: [PDFIncrementalUpdateDiagnostic]
}

struct PDFFormUpdatePlanner {
  let form: PDFAcroForm
  let fields: [PDFFormFieldIdentifier: PDFFormField]
  let transaction: PDFFormUpdateTransaction
  let limits: PDFIncrementalWritingLimits

  func plan() throws -> PDFFormUpdatePlan {
    guard !transaction.updates.isEmpty else {
      throw PDFIncrementalUpdateError.validationFailed
    }
    guard transaction.updates.count <= limits.maximumFieldUpdates else {
      throw PDFIncrementalUpdateError.limitExceeded
    }
    guard form.xfa == nil else { throw PDFIncrementalUpdateError.unsupportedXFA }
    var seen = Set<PDFFormFieldIdentifier>()
    var objects = [PDFObjectReference: PDFIncrementalObjectBody]()
    var diagnostics = [PDFIncrementalUpdateDiagnostic]()
    for update in transaction.updates {
      guard seen.insert(update.field).inserted else {
        throw PDFIncrementalUpdateError.duplicateField(update.field)
      }
      guard let field = fields[update.field] else {
        throw PDFIncrementalUpdateError.unknownField(update.field)
      }
      try validate(field)
      let normalized = try normalizedValue(update.value, for: field)
      var dictionary = field.rawDictionary
      if let value = normalized.value {
        dictionary["V"] = value
      } else {
        dictionary["V"] = nil
      }
      if let indices = normalized.indices, !indices.isEmpty {
        dictionary["I"] = .array(indices.map(PDFObject.integer))
      } else {
        dictionary["I"] = nil
      }
      switch update.richText {
      case .remove:
        dictionary["RV"] = nil
      case .replace(let value):
        guard field.type == .text, field.flags.contains(.richText) else {
          throw invalid(field, "Rich text is valid only for a rich-text text field.")
        }
        dictionary["RV"] = .string(value)
      }
      objects[field.identifier.reference] = .value(.dictionary(dictionary))

      if field.type == .button {
        let state = normalized.buttonState ?? "Off"
        for widget in field.widgets {
          var widgetDictionary = widget.rawDictionary
          widgetDictionary["AS"] = .name(state)
          objects[widget.annotationIdentifier.reference] = .value(.dictionary(widgetDictionary))
        }
      }
      if !field.actions.isEmpty {
        diagnostics.append(.init(
          kind: .actionsNotExecuted,
          message: "Actions associated with \(field.fullyQualifiedName ?? "an unnamed field") were retained but not executed."
        ))
      }
    }
    guard objects.count <= limits.maximumAppendedObjects else {
      throw PDFIncrementalUpdateError.limitExceeded
    }
    return PDFFormUpdatePlan(
      objects: objects,
      changedReferences: objects.keys.sorted(),
      newReferences: [],
      diagnostics: diagnostics
    )
  }

  private func validate(_ field: PDFFormField) throws {
    guard field.children.isEmpty else { throw invalid(field, "Only terminal fields may be updated.") }
    guard !field.flags.contains(.readOnly) else { throw PDFIncrementalUpdateError.permissionDenied }
    guard field.type != .signature else { throw invalid(field, "Signature fields are immutable.") }
    guard !(field.type == .button && field.flags.contains(.pushButton)) else {
      throw invalid(field, "Push buttons do not retain a form value.")
    }
    guard field.type != nil else { throw invalid(field, "The terminal field has no field type.") }
  }

  private func normalizedValue(
    _ requested: PDFFormFieldUpdateValue,
    for field: PDFFormField
  ) throws -> NormalizedValue {
    if case .resetToDefault = requested {
      return try normalizedExisting(field.defaultValue, for: field)
    }
    if case .clear = requested {
      guard !field.flags.contains(.required) else { throw invalid(field, "A required field cannot be cleared.") }
      return field.type == .button
        ? NormalizedValue(value: .name("Off"), indices: nil, buttonState: "Off")
        : NormalizedValue(value: nil, indices: nil, buttonState: nil)
    }
    switch field.type {
    case .text:
      let string: PDFString = switch requested {
      case .text(let value): encodeText(value)
      case .encodedText(let value): value
      default: throw invalid(field, "A text field requires a text value.")
      }
      try validateLength(of: string, field: field)
      return NormalizedValue(value: .string(string), indices: nil, buttonState: nil)
    case .choice:
      return try normalizedChoice(requested, field: field)
    case .button:
      guard case .button(let requestedState) = requested else {
        throw invalid(field, "A button field requires an appearance-state name.")
      }
      let state = requestedState ?? "Off"
      if state == PDFName("Off"), field.flags.contains(.noToggleToOff) {
        throw invalid(field, "This button may not be toggled off.")
      }
      return NormalizedValue(value: .name(state), indices: nil, buttonState: state)
    case .signature, nil:
      throw invalid(field, "The field type cannot accept a value update.")
    }
  }

  private func normalizedExisting(
    _ value: PDFFormValue?,
    for field: PDFFormField
  ) throws -> NormalizedValue {
    guard let value else {
      guard !field.flags.contains(.required) else { throw invalid(field, "A required field has no default value.") }
      return field.type == .button
        ? NormalizedValue(value: .name("Off"), indices: nil, buttonState: "Off")
        : NormalizedValue(value: nil, indices: nil, buttonState: nil)
    }
    switch value {
    case .string(let string):
      try validateLength(of: string, field: field)
      return NormalizedValue(value: .string(string), indices: nil, buttonState: nil)
    case .strings(let strings):
      return NormalizedValue(value: .array(strings.map(PDFObject.string)), indices: nil, buttonState: nil)
    case .name(let name):
      return NormalizedValue(value: .name(name), indices: nil, buttonState: name)
    case .null:
      return NormalizedValue(value: nil, indices: nil, buttonState: nil)
    case .other:
      throw invalid(field, "The default field value has an unsupported representation.")
    }
  }

  private func normalizedChoice(
    _ requested: PDFFormFieldUpdateValue,
    field: PDFFormField
  ) throws -> NormalizedValue {
    let supplied: [PDFString]
    let comparesExactBytes: Bool
    switch requested {
    case .choice(let values):
      supplied = values.map(encodeText)
      comparesExactBytes = false
    case .encodedChoice(let values):
      supplied = values
      comparesExactBytes = true
    case .text(let value) where field.flags.contains(.combo) && field.flags.contains(.edit):
      supplied = [encodeText(value)]
      comparesExactBytes = false
    case .encodedText(let value) where field.flags.contains(.combo) && field.flags.contains(.edit):
      supplied = [value]
      comparesExactBytes = true
    default:
      throw invalid(field, "A choice field requires choice values.")
    }
    guard field.flags.contains(.multiSelect) || supplied.count <= 1 else {
      throw invalid(field, "The choice field does not permit multiple selections.")
    }
    let options = try field.options.enumerated().map { index, object in
      try choiceOption(object, index: index)
    }
    var indices = [Int]()
    for value in supplied {
      let matches = try options.filter { option in
        if comparesExactBytes { return option.export.bytes == value.bytes }
        return try decoded(option.export) == decoded(value)
      }
      if matches.isEmpty, field.flags.contains(.combo), field.flags.contains(.edit), supplied.count == 1 {
        continue
      }
      guard matches.count == 1, let match = matches.first else {
        throw invalid(field, matches.isEmpty ? "A selected choice is unavailable." : "A selected choice is ambiguous.")
      }
      indices.append(match.index)
    }
    let value: PDFObject = supplied.count == 1
      ? .string(supplied[0])
      : .array(supplied.map(PDFObject.string))
    return NormalizedValue(value: value, indices: indices.sorted(), buttonState: nil)
  }

  private func choiceOption(_ object: PDFObject, index: Int) throws -> ChoiceOption {
    switch object {
    case .string(let value):
      return ChoiceOption(index: index, export: value)
    case .array(let values) where values.count == 2:
      guard case .string(let export) = values[0], case .string = values[1] else {
        throw PDFIncrementalUpdateError.validationFailed
      }
      return ChoiceOption(index: index, export: export)
    default:
      throw PDFIncrementalUpdateError.validationFailed
    }
  }

  private func validateLength(of string: PDFString, field: PDFFormField) throws {
    guard let maximumLength = field.maximumLength else { return }
    let count = (try? decoded(string).count) ?? string.bytes.count
    guard count <= maximumLength else { throw invalid(field, "The value exceeds MaxLen.") }
  }

  private func encodeText(_ value: String) -> PDFString {
    var data = Data([0xFE, 0xFF])
    for unit in value.utf16 {
      data.append(UInt8(unit >> 8))
      data.append(UInt8(unit & 0xFF))
    }
    return PDFString(bytes: data, representation: .hexadecimal)
  }

  private func decoded(_ value: PDFString) throws -> String {
    try PDFTextStringDecoder.decode(value, allowsUTF8: true)
  }

  private func invalid(_ field: PDFFormField, _ reason: String) -> PDFIncrementalUpdateError {
    .invalidFieldValue(field.identifier, reason: reason)
  }
}

private struct NormalizedValue {
  let value: PDFObject?
  let indices: [Int]?
  let buttonState: PDFName?
}

private struct ChoiceOption {
  let index: Int
  let export: PDFString
}
