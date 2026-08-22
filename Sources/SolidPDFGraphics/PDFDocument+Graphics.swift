import SolidPDF
import SolidPostScript

extension PDFDocument {
  /// Interprets one page from the latest revision through `target`.
  public func render<Target: GraphicsTarget>(
    page index: Int,
    to target: Target,
    options: PDFGraphicsInterpretationOptions = .init(),
    fontEnvironment: PDFGraphicsFontEnvironment = .portable
  ) async throws -> PDFGraphicsRenderResult<Target.Output> {
    try await render(
      selection: .indices([index]), in: latestRevision.identifier, to: target,
      options: options, fontEnvironment: fontEnvironment
    )
  }

  /// Interprets selected pages from the latest revision through `target`.
  public func render<Target: GraphicsTarget>(
    selection: PDFGraphicsPageSelection = .all,
    to target: Target,
    options: PDFGraphicsInterpretationOptions = .init(),
    fontEnvironment: PDFGraphicsFontEnvironment = .portable
  ) async throws -> PDFGraphicsRenderResult<Target.Output> {
    try await render(
      selection: selection, in: latestRevision.identifier, to: target,
      options: options, fontEnvironment: fontEnvironment
    )
  }

  /// Interprets selected pages from one document revision through `target`.
  public func render<Target: GraphicsTarget>(
    selection: PDFGraphicsPageSelection,
    in revision: PDFRevisionIdentifier,
    to target: Target,
    options: PDFGraphicsInterpretationOptions = .init(),
    fontEnvironment: PDFGraphicsFontEnvironment = .portable
  ) async throws -> PDFGraphicsRenderResult<Target.Output> {
    try checkPermission(options.accessPurpose)
    let selected = try await selectedPageIndices(selection, revision: revision)
    let pageDevice = try target.pageDeviceProvider.makeSession(for: target.deviceDescriptor)
    let color = try target.colorEngine.makeSession(for: target.deviceDescriptor)
    let deviceRendering = try target.deviceRenderingEngine.makeSession(for: target.deviceDescriptor)
    let font = try target.fontEngine.makeSession(for: target.deviceDescriptor)
    let trapping = try target.trappingEngine.makeSession(for: target.deviceDescriptor)
    let renderer = try target.makeRenderer(
      colorSession: color,
      deviceRenderingSession: deviceRendering,
      fontSession: font,
      trappingSession: trapping
    )
    let output = PDFGraphicsRendererOutput(renderer: renderer)
    var rendered: [PDFRenderedPage] = []
    var diagnostics: [PDFGraphicsDiagnostic] = []
    do {
      for (ordinal, pageIndex) in selected.enumerated() {
        try Task.checkCancellation()
        let page = try await page(at: pageIndex, in: revision)
        let boundary = pageBoundary(options.pageBoundary, geometry: page.geometry)
        let pageSize = orientedPageSize(boundary, geometry: page.geometry)
        let initial = pageDevice.initialConfiguration
        let negotiation = try pageDevice.negotiate(GraphicsPageDeviceRequest(
          pageSize: pageSize,
          resolution: .init(
            width: initial.descriptor.horizontalResolution,
            height: initial.descriptor.verticalResolution
          ),
          imagingBoundingBox: nil,
          numberOfCopies: 1,
          colorants: initial.colorants,
          trappingEnabled: false,
          trappingDetails: initial.trappingDetails,
          usesCIEColor: false,
          outputDevice: initial.outputDevice,
          inputMedia: initial.inputMedia,
          outputDestinations: initial.outputDestinations,
          placement: .simplex,
          delivery: .virtual
        ))
        guard negotiation.unsatisfiedParameters.isEmpty else {
          throw PDFGraphicsError.targetFailure(
            "Target rejected PDF page geometry: \(negotiation.unsatisfiedParameters.sorted().joined(separator: ", "))."
          )
        }
        let descriptor = pdfDescriptor(
          negotiation.configuration.descriptor,
          boundary: boundary,
          geometry: page.geometry
        )
        let device = GraphicsDeviceSnapshot(
          identifier: negotiation.configuration.identifier,
          outputDeviceIdentifier: negotiation.configuration.outputDeviceIdentifier,
          kind: .page,
          descriptor: descriptor,
          pageNumber: ordinal,
          numberOfCopies: 1,
          trapping: .disabled,
          usesCIEColor: false,
          mediaSelection: negotiation.configuration.mediaSelection,
          placement: negotiation.configuration.placement,
          delivery: negotiation.configuration.delivery
        )
        try targetCall { try renderer.activateDevice(device) }
        let resources = PDFGraphicsResourceResolver(
          document: self,
          revision: revision,
          resources: page.resources.value,
          limits: options.limits,
          fontEnvironment: fontEnvironment,
          strict: options.strict
        )
        let handler = PDFGraphicsInstructionHandler(
          device: device,
          resources: resources,
          limits: options.limits,
          output: output
        )
        let input = PDFContentInput(streams: page.contentStreams) { [self] stream in
          try await decodedStream(of: stream)
        }
        let parser = PDFContentParser(
          input: input,
          revision: revision,
          page: page,
          maximumScratchBytes: options.limits.maximumScratchBytes
        )
        try await PDFContentExecutor(
          parser: parser,
          handler: handler,
          maximumOperators: options.limits.maximumOperatorsPerPage
        ).execute()
        diagnostics.append(contentsOf: handler.diagnostics)
        let snapshot = handler.currentSnapshot
        let origin = GraphicsEventOrigin(
          resourceIdentifier: GraphicsResourceIdentifier(
            rawValue: "pdf:r\(revision.ordinal):o\(page.reference.objectNumber):\(page.reference.generationNumber)"
          )
        )
        let event = GraphicsEvent(
          operation: .page(.show),
          before: snapshot,
          after: snapshot,
          origin: origin
        )
        try targetCall {
          try renderer.transmitPage(event, transmission: GraphicsPageTransmission(
            trigger: .showPage,
            logicalOrdinal: ordinal + 1,
            copies: 1,
            mediaSelection: device.mediaSelection,
            placement: device.placement,
            delivery: device.delivery
          ))
          try renderer.deactivateDevice(device)
        }
        rendered.append(PDFRenderedPage(
          revision: revision,
          pageIndex: page.index,
          pageReference: page.reference,
          device: device,
          coordinateMapping: GraphicsPageCoordinateMapping(device: descriptor),
          transmittedOrdinal: ordinal
        ))
      }
      return try PDFGraphicsRenderResult(
        output: targetFinish(renderer),
        pages: rendered,
        diagnostics: diagnostics
      )
    } catch {
      output.abortImage()
      renderer.abort()
      if error is CancellationError { throw error }
      if let error = error as? PDFGraphicsError { throw error }
      if let error = error as? PDFParsingError { throw error }
      throw PDFGraphicsError.targetFailure(String(describing: error))
    }
  }

  private func selectedPageIndices(
    _ selection: PDFGraphicsPageSelection,
    revision: PDFRevisionIdentifier
  ) async throws -> [Int] {
    switch selection {
    case .all: return Array(0..<(try await pageCount(in: revision)))
    case .indices(let indices):
      let count = try await pageCount(in: revision)
      guard let invalid = indices.first(where: { $0 < 0 || $0 >= count }) else { return indices }
      throw PDFParsingError.pageIndexOutOfRange(invalid)
    }
  }

  private func checkPermission(_ purpose: PDFGraphicsAccessPurpose) throws {
    guard let security else { return }
    let allowed = switch purpose {
    case .viewing: true
    case .extraction: security.effectivePermissions.contains(.extract)
    case .accessibilityExtraction: security.effectivePermissions.contains(.accessibility)
    case .printing: security.effectivePermissions.contains(.print)
    case .highQualityPrinting:
      security.effectivePermissions.contains(.print) && security.effectivePermissions.contains(.highQualityPrint)
    }
    guard allowed else { throw PDFGraphicsError.permissionDenied(purpose) }
  }

  private func pageBoundary(_ kind: PDFPageBoundaryKind, geometry: PDFPageGeometry) -> PDFRectangle {
    switch kind {
    case .media: geometry.mediaBox.effective
    case .crop: geometry.cropBox.effective
    case .bleed: geometry.bleedBox.effective
    case .trim: geometry.trimBox.effective
    case .art: geometry.artBox.effective
    }
  }

  private func orientedPageSize(_ rect: PDFRectangle, geometry: PDFPageGeometry) -> GraphicsSize {
    let width = (rect.maximumX - rect.minimumX) * geometry.userUnit.value
    let height = (rect.maximumY - rect.minimumY) * geometry.userUnit.value
    switch geometry.rotation.value {
    case .degrees90, .degrees270: return .init(width: height, height: width)
    case .degrees0, .degrees180: return .init(width: width, height: height)
    }
  }

  private func pdfDescriptor(
    _ descriptor: GraphicsDeviceDescriptor,
    boundary: PDFRectangle,
    geometry: PDFPageGeometry
  ) -> GraphicsDeviceDescriptor {
    let unit = geometry.userUnit.value
    let x0 = boundary.minimumX * unit
    let y0 = boundary.minimumY * unit
    let x1 = boundary.maximumX * unit
    let y1 = boundary.maximumY * unit
    let pageMatrix: GraphicsMatrix = switch geometry.rotation.value {
    case .degrees0: .init(a: unit, b: 0, c: 0, d: unit, tx: -x0, ty: -y0)
    case .degrees90: .init(a: 0, b: -unit, c: unit, d: 0, tx: -y0, ty: x1)
    case .degrees180: .init(a: -unit, b: 0, c: 0, d: -unit, tx: x1, ty: y1)
    case .degrees270: .init(a: 0, b: unit, c: -unit, d: 0, tx: y1, ty: -x0)
    }
    return GraphicsDeviceDescriptor(
      mediaBounds: descriptor.mediaBounds,
      imageableBounds: descriptor.imageableBounds,
      horizontalResolution: descriptor.horizontalResolution,
      verticalResolution: descriptor.verticalResolution,
      defaultMatrix: pageMatrix.concatenated(with: descriptor.defaultMatrix),
      defaultFlatness: descriptor.defaultFlatness,
      defaultStrokeAdjustment: descriptor.defaultStrokeAdjustment,
      minimumSmoothness: descriptor.minimumSmoothness,
      maximumSmoothness: descriptor.maximumSmoothness,
      defaultSmoothness: descriptor.defaultSmoothness,
      colorDevice: descriptor.colorDevice,
      deviceRendering: descriptor.deviceRendering,
      colorants: descriptor.colorants,
      trapping: descriptor.trapping
    )
  }

  private func targetCall(_ body: () throws -> Void) throws {
    do { try body() } catch { throw PDFGraphicsError.targetFailure(String(describing: error)) }
  }

  private func targetFinish<Renderer: GraphicsRenderer>(_ renderer: Renderer) throws -> Renderer.Output {
    do { return try renderer.finish() } catch { throw PDFGraphicsError.targetFailure(String(describing: error)) }
  }
}
