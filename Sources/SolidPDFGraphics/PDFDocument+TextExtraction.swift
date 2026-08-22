import Foundation
import SolidPDF
import SolidPostScript

extension PDFDocument {
  /// Opens a single-pass text extractor for the latest revision.
  public func extractedText(
    selection: PDFGraphicsPageSelection = .all,
    options: PDFTextExtractionOptions = .init()
  ) async throws -> PDFExtractedTextSequence {
    try await extractedText(selection: selection, in: latestRevision.identifier, options: options)
  }

  /// Opens a single-pass text extractor for a selected revision.
  public func extractedText(
    selection: PDFGraphicsPageSelection,
    in revision: PDFRevisionIdentifier,
    options: PDFTextExtractionOptions = .init()
  ) async throws -> PDFExtractedTextSequence {
    let indices: [Int]
    switch selection {
    case .all: indices = Array(0..<(try await pageCount(in: revision)))
    case .indices(let values):
      let count = try await pageCount(in: revision)
      for value in values where value < 0 || value >= count {
        throw PDFParsingError.pageIndexOutOfRange(value)
      }
      indices = values
    }
    return PDFExtractedTextSequence(state: PDFExtractedTextSequenceState(
      indices: indices,
      extract: { [self] index in
        try await extractTextPage(index, revision: revision, options: options)
      }
    ))
  }

  private func extractTextPage(
    _ index: Int,
    revision: PDFRevisionIdentifier,
    options: PDFTextExtractionOptions
  ) async throws -> PDFExtractedTextPage {
    let renderOptions = PDFGraphicsInterpretationOptions(
      accessPurpose: options.accessPurpose,
      strict: options.strict,
      limits: options.limits,
      optionalContentSelection: options.optionalContentSelection,
      optionalContentContext: options.optionalContentContext,
      annotationRenderingPolicy: options.includeAnnotations && options.includeAnnotationAppearances ? .all : .none
    )
    let result = try await render(
      selection: .indices([index]), in: revision, to: RecordingGraphicsTarget(),
      options: renderOptions, fontEnvironment: options.fontEnvironment
    )
    guard let recording = result.output.pages.first, let rendered = result.pages.first else {
      throw PDFGraphicsError.targetFailure("Text extraction did not receive a transmitted page.")
    }
    var records = try extractionRecords(
      recording.effects,
      includeHidden: options.includeHiddenContent,
      includeArtifacts: options.includeArtifacts,
      limits: options.limits
    )
    var diagnostics = result.diagnostics
    if options.includeAnnotations {
      let page = try await page(at: index, in: revision)
      let semantic = try await annotationRecords(
        page: page,
        revision: revision,
        mapping: rendered.coordinateMapping,
        includeHidden: options.includeHiddenContent,
        optionalContentSelection: options.optionalContentSelection,
        optionalContentContext: options.optionalContentContext,
        limits: options.limits
      )
      records = records.map { record in
        record.attachingFormValue(record.annotationIdentifier.flatMap { semantic.formValues[$0] })
      }
      records.append(contentsOf: semantic.records)
      diagnostics.append(contentsOf: staleAppearanceDiagnostics(
        appearanceRecords: records,
        semanticValues: semantic.formValues
      ))
    }
    let orderer = PDFStructureTextOrderer(
      document: self, revision: revision, pageIndex: index,
      pageReference: rendered.pageReference, records: records
    )
    let ordering = options.order == .structure
      ? try await orderer.order()
      : PDFTextRecordOrdering.physical(records.count)
    let spans = try extractionSpans(
      records: records,
      ordering: ordering,
      mapping: rendered.coordinateMapping,
      limits: options.limits
    )
    return PDFExtractedTextPage(
      revision: revision,
      pageIndex: index,
      pageReference: rendered.pageReference,
      spans: spans,
      diagnostics: diagnostics
    )
  }
}

private struct PDFExtractedRunRecord {
  let run: GraphicsGlyphRun?
  let path: [GraphicsMarkedContentScope]
  let visibility: GraphicsContentVisibility
  let bounds: GraphicsRect?
  let text: String?
  let replacementKey: GraphicsResourceIdentifier?
  let replacementText: String?
  let identifiers: [GraphicsMarkedContentIdentifier]
  let source: PDFExtractedTextSource
  let annotationIdentifier: PDFAnnotationIdentifier?
  let widgetIdentifier: PDFAnnotationIdentifier?
  let formFieldIdentifier: PDFFormFieldIdentifier?

  func attachingFormValue(
    _ value: (PDFFormFieldIdentifier, String)?
  ) -> Self {
    guard let value, let annotationIdentifier else { return self }
    return .init(
      run: run,
      path: path,
      visibility: visibility,
      bounds: bounds,
      text: text,
      replacementKey: replacementKey,
      replacementText: replacementText,
      identifiers: identifiers,
      source: .appearance(annotation: annotationIdentifier, field: value.0),
      annotationIdentifier: annotationIdentifier,
      widgetIdentifier: annotationIdentifier,
      formFieldIdentifier: value.0
    )
  }
}

private struct PDFTextRecordOrdering {
  var indices: [Int]
  var structurePaths: [Int: [PDFStructureElementIdentifier]]
  var structureReplacements: [Int: (PDFStructureElementIdentifier, String)]

  static func physical(_ count: Int) -> Self {
    .init(indices: Array(0..<count), structurePaths: [:], structureReplacements: [:])
  }
}

private struct PDFAnnotationExtractionRecords {
  let records: [PDFExtractedRunRecord]
  let formValues: [PDFAnnotationIdentifier: (PDFFormFieldIdentifier, String)]
}

private extension PDFDocument {
  func extractionRecords(
    _ effects: [GraphicsEffect],
    includeHidden: Bool,
    includeArtifacts: Bool,
    limits: PDFGraphicsLimits
  ) throws -> [PDFExtractedRunRecord] {
    var scopes = [GraphicsMarkedContentScope]()
    var records = [PDFExtractedRunRecord]()
    var textBytes = 0
    func visit(_ nestedEffects: [GraphicsEffect], depth: Int) throws {
      guard depth <= limits.maximumResourceDepth else {
        throw PDFGraphicsError.limitExceeded("Extracted display-list nesting limit exceeded.", location: nil)
      }
      for effect in nestedEffects {
        switch effect {
        case .markedContent(.begin(let scope), _): scopes.append(scope)
        case .markedContent(.end(let scope), _):
          guard scopes.last == scope else {
            throw PDFGraphicsError.targetFailure("Recorded marked-content boundaries are unbalanced.")
          }
          scopes.removeLast()
        case .markedContent(.point, _): break
        case .form(let form, _):
          try visit(form.displayList.effects, depth: depth + 1)
        case .transparencyGroup(let group, _):
          try visit(group.displayList.effects, depth: depth + 1)
        case .text(let run, _):
          let hidden = scopes.contains { !$0.visibility.isVisible }
          let artifact = scopes.contains { $0.properties.artifact != nil || $0.tag == Data("Artifact".utf8) }
          guard (includeHidden || !hidden), (includeArtifacts || !artifact) else { continue }
          guard records.count < limits.maximumExtractedTextSpans else {
            throw PDFGraphicsError.limitExceeded("Extracted text span limit exceeded.", location: nil)
          }
          let replacementScope = scopes.reversed().first { $0.properties.replacement != nil }
          let annotation = annotationIdentifier(in: scopes)
          let replacement = run.textReplacement ?? replacementScope?.properties.replacement
          let text = replacement == nil ? glyphText(run) : nil
          if let value = replacement?.text ?? text {
            let (total, overflow) = textBytes.addingReportingOverflow(value.utf8.count)
            guard !overflow, total <= limits.maximumExtractedTextBytes else {
              throw PDFGraphicsError.limitExceeded("Extracted text byte limit exceeded.", location: nil)
            }
            textBytes = total
          }
          records.append(.init(
            run: run,
            path: scopes,
            visibility: hidden
              ? .hidden(scopes.flatMap { scope -> [GraphicsResourceIdentifier] in
                if case .hidden(let identifiers) = scope.visibility { return identifiers }
                return []
              })
              : .visible,
            bounds: glyphBounds(run),
            text: text,
            replacementKey: replacementScope?.resourceIdentifier,
            replacementText: replacement?.text,
            identifiers: scopes.compactMap(\.properties.identifier),
            source: annotation.map { .appearance(annotation: $0, field: nil) } ?? .pageContent,
            annotationIdentifier: annotation,
            widgetIdentifier: annotation,
            formFieldIdentifier: nil
          ))
        default: break
        }
      }
    }
    try visit(effects, depth: 0)
    guard scopes.isEmpty else {
      throw PDFGraphicsError.targetFailure("Recorded marked-content boundaries are unbalanced.")
    }
    return records
  }

  func extractionSpans(
    records: [PDFExtractedRunRecord],
    ordering: PDFTextRecordOrdering,
    mapping: GraphicsPageCoordinateMapping,
    limits: PDFGraphicsLimits
  ) throws -> [PDFExtractedTextSpan] {
    var result = [PDFExtractedTextSpan]()
    var offset = 0
    while offset < ordering.indices.count {
      let firstIndex = ordering.indices[offset]
      let first = records[firstIndex]
      let structureReplacement = ordering.structureReplacements[firstIndex]
      let replacementIdentity = structureReplacement.map { "structure:\($0.0.reference.objectNumber)" }
        ?? first.replacementKey.map(\.rawValue)
      var indices = [firstIndex]
      var next = offset + 1
      while let replacementIdentity, next < ordering.indices.count {
        let candidateIndex = ordering.indices[next]
        let candidate = records[candidateIndex]
        let candidateStructure = ordering.structureReplacements[candidateIndex]
          .map { "structure:\($0.0.reference.objectNumber)" }
        let candidateIdentity = candidateStructure ?? candidate.replacementKey?.rawValue
        guard candidateIdentity == replacementIdentity else { break }
        indices.append(candidateIndex)
        next += 1
      }
      let selected = indices.map { records[$0] }
      let text = structureReplacement?.1 ?? first.replacementText
        ?? selected.compactMap(\.text).joined()
      let bounds = union(selected.compactMap(\.bounds))
      result.append(PDFExtractedTextSpan(
        source: first.source,
        text: text,
        runs: selected.compactMap(\.run),
        markedContentPath: first.path,
        structurePath: ordering.structurePaths[firstIndex] ?? [],
        visibility: first.visibility,
        deviceBounds: bounds,
        pageBounds: bounds.flatMap { rectangle in
          mapping.deviceToPage.map { transformedBounds(rectangle, by: $0) }
        },
        annotationIdentifier: first.annotationIdentifier,
        widgetIdentifier: first.widgetIdentifier,
        formFieldIdentifier: first.formFieldIdentifier
      ))
      offset = replacementIdentity == nil ? offset + 1 : next
    }
    guard result.count <= limits.maximumExtractedTextSpans else {
      throw PDFGraphicsError.limitExceeded("Extracted text span limit exceeded.", location: nil)
    }
    return result
  }

  func glyphText(_ run: GraphicsGlyphRun) -> String? {
    var scalars = String.UnicodeScalarView()
    for glyph in run.glyphs {
      guard let values = glyph.unicodeScalars else { return nil }
      scalars.append(contentsOf: values)
    }
    return String(scalars)
  }

  func annotationIdentifier(
    in scopes: [GraphicsMarkedContentScope]
  ) -> PDFAnnotationIdentifier? {
    for scope in scopes.reversed() {
      let components = scope.resourceIdentifier.rawValue.split(separator: ":")
      guard components.count >= 5,
        components[2] == "annotation",
        let objectNumber = Int(components[3]),
        let generation = Int(components[4]),
        let reference = try? PDFObjectReference(
          objectNumber: objectNumber,
          generationNumber: generation
        )
      else { continue }
      return .init(reference: reference)
    }
    return nil
  }

  func glyphBounds(_ run: GraphicsGlyphRun) -> GraphicsRect? {
    var rectangles = [GraphicsRect]()
    for glyph in run.glyphs {
      if let bounds = glyph.glyph.metrics.bounds {
        rectangles.append(transformedBounds(bounds, by: glyph.transform))
      } else {
        rectangles.append(.init(x: glyph.origin.x, y: glyph.origin.y, width: 0, height: 0))
      }
    }
    return union(rectangles)
  }

  func transformedBounds(_ rectangle: GraphicsRect, by matrix: GraphicsMatrix) -> GraphicsRect {
    let points = [
      GraphicsPoint(x: rectangle.x, y: rectangle.y),
      GraphicsPoint(x: rectangle.maxX, y: rectangle.y),
      GraphicsPoint(x: rectangle.x, y: rectangle.maxY),
      GraphicsPoint(x: rectangle.maxX, y: rectangle.maxY),
    ].map(matrix.transform)
    let minX = points.map(\.x).min() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxX = points.map(\.x).max() ?? minX
    let maxY = points.map(\.y).max() ?? minY
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  func union(_ rectangles: [GraphicsRect]) -> GraphicsRect? {
    guard let first = rectangles.first else { return nil }
    let minX = rectangles.dropFirst().reduce(first.x) { min($0, $1.x) }
    let minY = rectangles.dropFirst().reduce(first.y) { min($0, $1.y) }
    let maxX = rectangles.dropFirst().reduce(first.maxX) { max($0, $1.maxX) }
    let maxY = rectangles.dropFirst().reduce(first.maxY) { max($0, $1.maxY) }
    return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  func annotationRecords(
    page: PDFPage,
    revision: PDFRevisionIdentifier,
    mapping: GraphicsPageCoordinateMapping,
    includeHidden: Bool,
    optionalContentSelection: PDFOptionalContentSelection,
    optionalContentContext: PDFOptionalContentContext,
    limits: PDFGraphicsLimits
  ) async throws -> PDFAnnotationExtractionRecords {
    let annotations = try await annotations(on: page, in: revision)
    let fields = try await formFields(in: revision)
    var records = [PDFExtractedRunRecord]()
    var formValues = [PDFAnnotationIdentifier: (PDFFormFieldIdentifier, String)]()
    var annotationVisibility = [PDFAnnotationIdentifier: GraphicsContentVisibility]()
    for annotation in annotations {
      let optionalVisibility: GraphicsContentVisibility
      if let optionalContent = annotation.optionalContent {
        optionalVisibility = pdfGraphicsContentVisibility(try await optionalContentVisibility(
          of: optionalContent,
          selection: optionalContentSelection,
          context: optionalContentContext,
          in: revision
        ), revision: revision)
      } else {
        optionalVisibility = .visible
      }
      let hidden = annotation.flags.contains(.hidden) || annotation.flags.contains(.invisible)
        || !optionalVisibility.isVisible
      let visibility: GraphicsContentVisibility = optionalVisibility.isVisible
        ? hidden
          ? .hidden([.init(rawValue: "pdf:annotation-hidden:\(annotation.identifier.reference.objectNumber)")])
          : .visible
        : optionalVisibility
      annotationVisibility[annotation.identifier] = visibility
      guard includeHidden || !hidden else { continue }
      let pageBounds = GraphicsRect(
        x: annotation.rectangle.minimumX,
        y: annotation.rectangle.minimumY,
        width: annotation.rectangle.maximumX - annotation.rectangle.minimumX,
        height: annotation.rectangle.maximumY - annotation.rectangle.minimumY
      )
      let deviceBounds = transformedBounds(pageBounds, by: mapping.pageToDevice)
      var values = [String]()
      if let contents = annotation.contents { values.append(contents) }
      if let alternate = annotation.alternateDescription, !values.contains(alternate) { values.append(alternate) }
      for value in values {
        records.append(PDFExtractedRunRecord(
          run: nil,
          path: [],
          visibility: visibility,
          bounds: deviceBounds,
          text: value,
          replacementKey: nil,
          replacementText: nil,
          identifiers: [],
          source: .annotationText(annotation.identifier),
          annotationIdentifier: annotation.identifier,
          widgetIdentifier: nil,
          formFieldIdentifier: nil
        ))
      }
    }
    for field in fields where field.type != .signature && !field.flags.contains(.password) {
      guard let value = extractionFieldValue(field.value), !value.isEmpty else { continue }
      for widget in field.widgets where widget.pageReference == page.reference {
        let annotation = annotations.first { $0.identifier == widget.annotationIdentifier }
        let hiddenByFlag = annotation.map {
          $0.flags.contains(.hidden) || $0.flags.contains(.invisible)
        } ?? false
        let hidden = hiddenByFlag || annotationVisibility[widget.annotationIdentifier]?.isVisible == false
        guard includeHidden || !hidden else { continue }
        let pageBounds = GraphicsRect(
          x: widget.rectangle.minimumX,
          y: widget.rectangle.minimumY,
          width: widget.rectangle.maximumX - widget.rectangle.minimumX,
          height: widget.rectangle.maximumY - widget.rectangle.minimumY
        )
        let deviceBounds = transformedBounds(pageBounds, by: mapping.pageToDevice)
        let visibility = annotationVisibility[widget.annotationIdentifier] ?? (hidden
          ? .hidden([.init(rawValue: "pdf:annotation-hidden:\(widget.annotationIdentifier.reference.objectNumber)")])
          : .visible)
        records.append(PDFExtractedRunRecord(
          run: nil,
          path: [],
          visibility: visibility,
          bounds: deviceBounds,
          text: value,
          replacementKey: nil,
          replacementText: nil,
          identifiers: [],
          source: .formValue(field: field.identifier, widget: widget.annotationIdentifier),
          annotationIdentifier: widget.annotationIdentifier,
          widgetIdentifier: widget.annotationIdentifier,
          formFieldIdentifier: field.identifier
        ))
        formValues[widget.annotationIdentifier] = (field.identifier, value)
      }
    }
    guard records.count <= limits.maximumExtractedTextSpans else {
      throw PDFGraphicsError.limitExceeded("Extracted annotation text span limit exceeded.", location: nil)
    }
    return .init(records: records, formValues: formValues)
  }

  func extractionFieldValue(_ value: PDFFormValue?) -> String? {
    switch value {
    case .string(let string): return extractionText(string)
    case .strings(let strings): return strings.map(extractionText).joined(separator: "\n")
    case .name(let name): return String(data: name.bytes, encoding: .utf8)
    case .null, .other, nil: return nil
    }
  }

  func extractionText(_ string: PDFString) -> String {
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

  func staleAppearanceDiagnostics(
    appearanceRecords: [PDFExtractedRunRecord],
    semanticValues: [PDFAnnotationIdentifier: (PDFFormFieldIdentifier, String)]
  ) -> [PDFGraphicsDiagnostic] {
    semanticValues.compactMap { annotation, value in
      let appearance = appearanceRecords
        .filter { $0.annotationIdentifier == annotation && $0.run != nil }
        .compactMap(\.text)
        .joined()
      guard !appearance.isEmpty, appearance != value.1 else { return nil }
      return PDFGraphicsDiagnostic(
        identifier: "pdf.form.stale-appearance",
        message: "The widget appearance text disagrees with the authoritative field value.",
        severity: .warning,
        annotation: annotation
      )
    }
  }
}

private final class PDFStructureTextOrderer<Source: PDFInputSource> {
  let document: PDFDocument<Source>
  let revision: PDFRevisionIdentifier
  let pageIndex: Int
  let pageReference: PDFObjectReference
  let records: [PDFExtractedRunRecord]
  var visited = Set<PDFStructureElementIdentifier>()
  var paths = [Int: [PDFStructureElementIdentifier]]()
  var replacements = [Int: (PDFStructureElementIdentifier, String)]()

  init(
    document: PDFDocument<Source>, revision: PDFRevisionIdentifier, pageIndex: Int,
    pageReference: PDFObjectReference, records: [PDFExtractedRunRecord]
  ) {
    self.document = document
    self.revision = revision
    self.pageIndex = pageIndex
    self.pageReference = pageReference
    self.records = records
  }

  func order() async throws -> PDFTextRecordOrdering {
    guard let tree = try await document.structureTree(in: revision) else {
      return .physical(records.count)
    }
    var ordered = [Int]()
    for child in tree.children {
      if case .element(let identifier) = child {
        ordered.append(contentsOf: try await visit(identifier, path: []))
      }
    }
    let included = Set(ordered)
    ordered.append(contentsOf: records.indices.filter { !included.contains($0) })
    return .init(indices: ordered, structurePaths: paths, structureReplacements: replacements)
  }

  private func visit(
    _ identifier: PDFStructureElementIdentifier,
    path: [PDFStructureElementIdentifier]
  ) async throws -> [Int] {
    guard visited.insert(identifier).inserted else { return [] }
    let element = try await document.structureElement(identifier, in: revision)
    let currentPath = path + [identifier]
    var result = [Int]()
    for child in element.children {
      switch child {
      case .element(let childIdentifier):
        result.append(contentsOf: try await visit(childIdentifier, path: currentPath))
      case .markedContent(let reference):
        guard reference.page == nil || reference.page == pageReference else { continue }
        let owner = reference.stream.map {
          "pdf:r\(revision.ordinal):o\($0.objectNumber):\($0.generationNumber)"
        }
        for index in records.indices where records[index].identifiers.contains(where: {
          $0.value == reference.markedContentIdentifier && (owner == nil || $0.owner.rawValue == owner)
        }) {
          if !result.contains(index) { result.append(index) }
          paths[index] = currentPath
        }
      case .object(let reference):
        guard reference.page == nil || reference.page == pageReference else { continue }
        for index in records.indices where records[index].annotationIdentifier?.reference == reference.object {
          if !result.contains(index) { result.append(index) }
          paths[index] = currentPath
        }
      }
    }
    if let replacement = element.replacementText {
      for index in result { replacements[index] = (identifier, replacement) }
    }
    return result
  }
}
