import Foundation

/// A portable target that produces an authoritative physical print-delivery plan.
public struct PrintSpoolGraphicsTarget: GraphicsTarget, Sendable {
  public typealias PageOutput = GraphicsPrintPage
  public typealias Output = GraphicsPrintSpool

  /// Per-render print-spool renderer.
  public final class Renderer: GraphicsRenderer {
    public typealias PageOutput = GraphicsPrintPage
    public typealias Output = GraphicsPrintSpool

    private struct SectionKey: Hashable {
      let outputDevice: GraphicsOutputDeviceIdentifier
      let destination: GraphicsOutputDestination?
      let copies: Int
      let media: GraphicsMediaSelection
      let duplex: Bool
      let outputFace: GraphicsOutputFace
    }

    private struct PendingSection {
      let key: SectionKey
      let copies: Int
      let delivery: GraphicsPageDeliveryConfiguration
      var pageIndices: [Int]
    }

    /// Logical pages captured so far.
    public private(set) var pages: [GraphicsPrintPage] = []

    private let limits: GraphicsPrintSpoolLimits
    private let collector = GraphicsEffectCollector()
    private var sheets: [GraphicsPrintSheet] = []
    private var pageSets: [GraphicsPrintPageSet] = []
    private var actions: [GraphicsPrintDeliveryAction] = []
    private var pendingSection: PendingSection?
    private var openSheetIndex: Int?
    private var planningBytes = 0
    private var deliveredSideCount = 0
    private var currentDevice: GraphicsDeviceSnapshot?
    private var lastDelivery = GraphicsPageDeliveryConfiguration.virtual
    private var renderingEnabled = true
    private var aborted = false
    private let storage = GraphicsStorageTracker()

    fileprivate init(limits: GraphicsPrintSpoolLimits) {
      self.limits = limits
    }

    /// Captures one realized graphics effect.
    public func process(_ event: GraphicsEvent) {
      guard !aborted, renderingEnabled else { return }
      let previousCount = collector.effects.count
      collector.process(event)
      if !storage.updateCurrentDeferringError(effects: collector.effects) {
        if collector.effects.count > previousCount { collector.removeLastEffect() }
      }
    }

    /// Begins a sampled-image capture.
    public func beginImage(_ event: GraphicsEvent) throws {
      guard !aborted, renderingEnabled else { return }
      try storage.beginImage()
      try collector.beginImage(event)
    }

    /// Captures sampled-image rows.
    public func writeImageRows(_ rows: GraphicsImageRows) throws {
      guard let current = collector.activeImageBytes else { throw Error.ioError }
      let values = rows.components.count.addingReportingOverflow(rows.sourceComponents?.count ?? 0)
      let additional = values.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      let rowBytes = additional.partialValue.addingReportingOverflow(rows.rawSamples?.count ?? 0)
      let total = current.addingReportingOverflow(rowBytes.partialValue)
      guard !values.overflow, !additional.overflow, !rowBytes.overflow, !total.overflow else {
        throw GraphicsStorageAccountingError.limitExceeded
      }
      try storage.resizeImage(to: total.partialValue)
      try collector.writeImageRows(rows)
    }

    /// Captures sampled-image mask rows.
    public func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
      guard let current = collector.activeImageBytes else { throw Error.ioError }
      let additional = rows.opacities.count.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      let total = current.addingReportingOverflow(additional.partialValue)
      guard !additional.overflow, !total.overflow else {
        throw GraphicsStorageAccountingError.limitExceeded
      }
      try storage.resizeImage(to: total.partialValue)
      try collector.writeImageMaskRows(rows)
    }

    /// Completes a sampled-image capture.
    public func endImage() throws {
      try collector.endImage()
      do {
        try storage.endImage(effects: collector.effects)
      } catch {
        collector.removeLastEffect()
        throw error
      }
    }

    /// Abandons an incomplete sampled-image capture.
    public func abortImage() {
      collector.abortImage()
      storage.abortImage()
    }

    /// Activates one print or null device.
    public func activateDevice(_ device: GraphicsDeviceSnapshot) {
      currentDevice = device
      renderingEnabled = device.kind == .page
    }

    /// Records device-deactivation delivery actions without forcing a compatible collated section closed.
    public func deactivateDevice(_ device: GraphicsDeviceSnapshot) throws {
      try schedule(delivery: device.delivery, mode: .deviceDeactivation, boundary: .deviceDeactivation)
      if device.delivery.jog == .deviceDeactivation { appendAction(.jog, boundary: .deviceDeactivation) }
      collector.clear()
      storage.clearCurrent()
      currentDevice = nil
    }

    /// Preserves source compatibility with callers that provide only a copy count.
    public func transmitPage(_ event: GraphicsEvent, copies: Int) throws {
      try transmitPage(event, transmission: GraphicsPageTransmission(
        trigger: event.operation == .page(.copy) ? .copyPage : .showPage,
        logicalOrdinal: pages.count + 1,
        copies: copies
      ))
    }

    /// Captures and schedules one logical page transmission.
    public func transmitPage(
      _ event: GraphicsEvent,
      transmission: GraphicsPageTransmission
    ) throws {
      guard !aborted, transmission.copies >= 0 else { throw Error.ioError }
      lastDelivery = transmission.delivery
      defer { collector.clear() }
      guard transmission.copies > 0 else {
        storage.transmit(retainingPage: false)
        return
      }
      guard pages.count < limits.maximumLogicalPages else { throw Error.limitCheck }
      let separationCount = event.before.device.descriptor.colorants.producesSeparations
        ? event.before.device.descriptor.colorants.separationOrder.count
        : 1
      let pageSides = transmission.copies.multipliedReportingOverflow(by: separationCount)
      let currentSides = deliveredSideCount.addingReportingOverflow(pendingSideCount())
      guard !pageSides.overflow, !currentSides.overflow else { throw Error.limitCheck }
      let plannedSides = currentSides.partialValue.addingReportingOverflow(pageSides.partialValue)
      guard !plannedSides.overflow, plannedSides.partialValue <= limits.maximumDeliveredSides else {
        throw Error.limitCheck
      }
      let effects = transmission.mediaSelection.isInsertedSheet ? [] : collector.effects
      let footprint = GraphicsDisplayList(effects: effects).checkedFootprint()
      let total = planningBytes.addingReportingOverflow(footprint)
      guard !total.overflow, total.partialValue <= limits.maximumPlanningBytes else {
        throw Error.limitCheck
      }
      let page = GraphicsPrintPage(
        index: pages.count,
        device: event.before.device,
        effects: effects,
        transmission: transmission,
        isInsertedSheet: transmission.mediaSelection.isInsertedSheet
      )
      pages.append(page)
      planningBytes = total.partialValue
      storage.transmit(retainingPage: true)

      if transmission.delivery.collates {
        try appendCollated(page)
      } else {
        try finalizePendingSection()
        try appendUncollated(page)
      }
      try schedule(
        delivery: transmission.delivery,
        mode: .pageTransmission,
        boundary: .pageTransmission
      )
    }

    /// Completes collation, physical packing, and normal end-of-job actions.
    public func finish() throws -> sending GraphicsPrintSpool {
      try finalizePendingSection()
      openSheetIndex = nil
      try schedule(delivery: lastDelivery, mode: .jobCompletion, boundary: .jobCompletion)
      if lastDelivery.jog == .jobCompletion { appendAction(.jog, boundary: .jobCompletion) }
      let physical = sheets.map(\.index)
      let stack = stackReadOrder()
      let output = GraphicsPrintSpool(
        pages: pages,
        sheets: sheets,
        pageSets: pageSets,
        actions: actions,
        physicalDeliveryOrder: physical,
        stackReadOrder: stack
      )
      storage.releaseAll()
      return output
    }

    /// Abandons the entire spool.
    public func abort() {
      aborted = true
      collector.clear()
      pages.removeAll()
      sheets.removeAll()
      pageSets.removeAll()
      actions.removeAll()
      deliveredSideCount = 0
      pendingSection = nil
      openSheetIndex = nil
      storage.releaseAll()
    }

    /// Installs Appendix C accounting for retained print-planning storage.
    public func installStorageAccounting(_ session: GraphicsStorageAccountingSession) {
      storage.install(session)
    }

    public func takeStorageAccountingError() -> GraphicsStorageAccountingError? {
      storage.takeError()
    }

    private func appendCollated(_ page: GraphicsPrintPage) throws {
      let key = SectionKey(
        outputDevice: page.device.outputDeviceIdentifier,
        destination: page.transmission.delivery.destination,
        copies: page.transmission.copies,
        media: page.transmission.mediaSelection,
        duplex: page.transmission.placement.isDuplex,
        outputFace: page.transmission.delivery.outputFace
      )
      if pendingSection?.key != key {
        try finalizePendingSection()
        pendingSection = PendingSection(
          key: key,
          copies: page.transmission.copies,
          delivery: page.transmission.delivery,
          pageIndices: []
        )
      }
      pendingSection?.pageIndices.append(page.index)
    }

    private func appendUncollated(_ page: GraphicsPrintPage) throws {
      let ordinal = pageSets.count + 1
      let firstSheet = sheets.count
      for copy in 1...page.transmission.copies {
        try appendPageSides(page, copyOrdinal: copy, pageSetOrdinal: ordinal)
      }
      let touched = Array(firstSheet..<sheets.count)
      pageSets.append(GraphicsPrintPageSet(
        ordinal: ordinal,
        pageIndices: [page.index],
        sheetIndices: touched,
        isCollated: false
      ))
      try pageSetActions(for: page.transmission.delivery)
    }

    private func finalizePendingSection() throws {
      guard let section = pendingSection else { return }
      pendingSection = nil
      for copy in 1...section.copies {
        openSheetIndex = nil
        let ordinal = pageSets.count + 1
        let firstSheet = sheets.count
        for pageIndex in section.pageIndices {
          try appendPageSides(pages[pageIndex], copyOrdinal: copy, pageSetOrdinal: ordinal)
        }
        openSheetIndex = nil
        pageSets.append(GraphicsPrintPageSet(
          ordinal: ordinal,
          pageIndices: section.pageIndices,
          sheetIndices: Array(firstSheet..<sheets.count),
          isCollated: true
        ))
        try pageSetActions(for: section.delivery)
      }
    }

    private func appendPageSides(
      _ page: GraphicsPrintPage,
      copyOrdinal: Int,
      pageSetOrdinal: Int
    ) throws {
      let colorants: [String?] = page.device.descriptor.colorants.producesSeparations
        ? page.device.descriptor.colorants.separationOrder.map(Optional.some)
        : [nil]
      for colorant in colorants {
        try appendSide(
          page: page,
          colorant: colorant,
          copyOrdinal: copyOrdinal,
          pageSetOrdinal: pageSetOrdinal
        )
      }
    }

    private func appendSide(
      page: GraphicsPrintPage,
      colorant: String?,
      copyOrdinal: Int,
      pageSetOrdinal: Int
    ) throws {
      guard deliveredSideCount < limits.maximumDeliveredSides else { throw Error.limitCheck }
      let duplex = page.transmission.placement.isDuplex && !page.isInsertedSheet
      let canUseOpenSheet: Bool = if let openSheetIndex {
        duplex && sheets[openSheetIndex].back == nil
          && sheets[openSheetIndex].mediaSelection == page.transmission.mediaSelection
          && sheets[openSheetIndex].destination == page.transmission.delivery.destination
      } else {
        false
      }
      if canUseOpenSheet, let openSheetIndex {
        let previous = sheets[openSheetIndex]
        let side = GraphicsPrintSide(
          pageIndex: page.index,
          placement: page.transmission.placement.replacing(side: .verso),
          separationColorant: colorant,
          copyOrdinal: copyOrdinal,
          pageSetOrdinal: pageSetOrdinal,
          isInsertedSheet: page.isInsertedSheet
        )
        sheets[openSheetIndex] = GraphicsPrintSheet(
          index: previous.index,
          front: previous.front,
          back: side,
          mediaSelection: previous.mediaSelection,
          destination: previous.destination,
          outputFace: previous.outputFace
        )
        deliveredSideCount += 1
        self.openSheetIndex = nil
      } else {
        openSheetIndex = nil
        let side = GraphicsPrintSide(
          pageIndex: page.index,
          placement: page.transmission.placement.replacing(side: .recto),
          separationColorant: colorant,
          copyOrdinal: copyOrdinal,
          pageSetOrdinal: pageSetOrdinal,
          isInsertedSheet: page.isInsertedSheet
        )
        let index = sheets.count
        sheets.append(GraphicsPrintSheet(
          index: index,
          front: side,
          back: nil,
          mediaSelection: page.transmission.mediaSelection,
          destination: page.transmission.delivery.destination,
          outputFace: page.transmission.delivery.outputFace
        ))
        deliveredSideCount += 1
        if duplex { openSheetIndex = index }
      }
    }

    private func pageSetActions(for delivery: GraphicsPageDeliveryConfiguration) throws {
      try schedule(delivery: delivery, mode: .pageSet, boundary: .pageSet)
      if delivery.jog == .pageSet { appendAction(.jog, boundary: .pageSet) }
    }

    private func schedule(
      delivery: GraphicsPageDeliveryConfiguration,
      mode: GraphicsMediaActionMode,
      boundary: GraphicsPrintDeliveryAction.Boundary
    ) throws {
      if delivery.advanceMedia == mode {
        appendAction(.advance(distance: delivery.advanceDistance), boundary: boundary)
      }
      if delivery.cutMedia == mode { appendAction(.cut, boundary: boundary) }
    }

    private func appendAction(
      _ kind: GraphicsPrintDeliveryAction.Kind,
      boundary: GraphicsPrintDeliveryAction.Boundary
    ) {
      actions.append(GraphicsPrintDeliveryAction(
        ordinal: actions.count,
        kind: kind,
        boundary: boundary
      ))
    }

    private func pendingSideCount() -> Int {
      guard let pendingSection else { return 0 }
      return pendingSection.pageIndices.reduce(0) { partial, pageIndex in
        let page = pages[pageIndex]
        let separations = page.device.descriptor.colorants.producesSeparations
          ? page.device.descriptor.colorants.separationOrder.count
          : 1
        let product = pendingSection.copies.multipliedReportingOverflow(by: separations)
        guard !product.overflow else { return .max }
        let sum = partial.addingReportingOverflow(product.partialValue)
        return sum.overflow ? .max : sum.partialValue
      }
    }

    private func stackReadOrder() -> [Int] {
      var result: [Int] = []
      var start = 0
      while start < sheets.count {
        let destination = sheets[start].destination
        let face = sheets[start].outputFace
        var end = start + 1
        while end < sheets.count,
          sheets[end].destination == destination,
          sheets[end].outputFace == face
        {
          end += 1
        }
        let indexes = sheets[start..<end].map(\.index)
        result.append(contentsOf: face == .faceUp ? Array(indexes.reversed()) : indexes)
        start = end
      }
      return result
    }
  }

  /// Initial device geometry.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// Physical page-device provider used by this target.
  public let pageDeviceProvider: StandardGraphicsPageDeviceProvider
  /// Spool resource limits.
  public let limits: GraphicsPrintSpoolLimits

  /// Creates a portable print-spool target.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor = .letter,
    inputMedia: GraphicsMediaCatalog? = nil,
    outputDestinations: GraphicsOutputCatalog? = nil,
    limits: GraphicsPrintSpoolLimits = .init()
  ) {
    self.deviceDescriptor = deviceDescriptor
    self.limits = limits
    let pageSize = GraphicsSize(
      width: deviceDescriptor.mediaBounds.width * 72 / deviceDescriptor.horizontalResolution,
      height: deviceDescriptor.mediaBounds.height * 72 / deviceDescriptor.verticalResolution
    )
    let media = inputMedia ?? GraphicsMediaCatalog(sources: [
      0: GraphicsMediaSource(position: 0, attributes: GraphicsMediaAttributes(pageSize: pageSize)),
    ])
    let destinations = outputDestinations ?? GraphicsOutputCatalog(destinations: [
      0: GraphicsOutputDestination(position: 0, type: Data("Default".utf8)),
    ])
    self.pageDeviceProvider = StandardGraphicsPageDeviceProvider(
      mode: .adaptive,
      name: "SolidPrintSpoolDevice",
      colorantCapabilities: .semantic,
      trappingCapabilities: .semanticType1001,
      physicalCapabilities: .printSpool,
      inputMedia: media,
      outputDestinations: destinations,
      outputDeviceIdentifier: GraphicsOutputDeviceIdentifier()
    )
  }

  /// Creates a renderer dedicated to one print spool.
  public func makeRenderer() -> sending Renderer { Renderer(limits: limits) }
}

private extension GraphicsMediaSelection {
  var isInsertedSheet: Bool {
    if case let .selected(source) = self { return source.attributes?.insertsSheet == true }
    if case let .deferred(request) = self { return request.attributes.insertsSheet == true }
    return false
  }
}
