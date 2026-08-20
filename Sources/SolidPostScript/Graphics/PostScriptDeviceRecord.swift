import Foundation
import Synchronization

struct PostScriptDeviceTrappingState: Sendable {
  let configuration: GraphicsPageDeviceConfiguration?
  let pageNumber: Int
  let logicalTransmissionOrdinal: Int
  let snapshot: GraphicsTrappingSnapshot
  let defaultZones: [GraphicsTrappingZone]
  let trapSetNameSource: Object?
}

final class PostScriptDeviceRecord: Sendable {
  struct State: Sendable {
    var configuration: GraphicsPageDeviceConfiguration?
    var pageNumber: Int
    var logicalTransmissionOrdinal: Int
    var trapping: GraphicsTrappingSnapshot
    var defaultTrappingZones: [GraphicsTrappingZone]
    var trapSetNameSource: Object?
  }

  let identifier: GraphicsDeviceIdentifier
  let kind: GraphicsDeviceKind
  private let state: Mutex<State>

  init(configuration: GraphicsPageDeviceConfiguration) {
    self.identifier = configuration.identifier
    self.kind = .page
    self.state = Mutex(State(
      configuration: configuration,
      pageNumber: 0,
      logicalTransmissionOrdinal: 0,
      trapping: GraphicsTrappingSnapshot(
        enabled: configuration.trappingEnabled,
        details: configuration.trappingDetails,
        parameters: configuration.descriptor.trapping.defaultParameters
      ),
      defaultTrappingZones: [],
      trapSetNameSource: nil
    ))
    self.nullDescriptor = nil
  }

  init(nullDescriptor descriptor: GraphicsDeviceDescriptor) {
    self.identifier = GraphicsDeviceIdentifier()
    self.kind = .null
    self.state = Mutex(State(
      configuration: nil,
      pageNumber: 0,
      logicalTransmissionOrdinal: 0,
      trapping: .disabled,
      defaultTrappingZones: [],
      trapSetNameSource: nil
    ))
    self.nullDescriptor = descriptor
  }

  private let nullDescriptor: GraphicsDeviceDescriptor?

  var configuration: GraphicsPageDeviceConfiguration? {
    state.withLock { $0.configuration }
  }

  var descriptor: GraphicsDeviceDescriptor {
    configuration?.descriptor ?? nullDescriptor ?? .letter
  }

  var pageNumber: Int {
    state.withLock { $0.pageNumber }
  }

  var snapshot: GraphicsDeviceSnapshot {
    let current = state.withLock { $0 }
    return GraphicsDeviceSnapshot(
      identifier: identifier,
      kind: kind,
      descriptor: current.configuration?.descriptor ?? nullDescriptor ?? .letter,
      pageNumber: current.pageNumber,
      numberOfCopies: current.configuration?.numberOfCopies,
      trapping: current.trapping,
      usesCIEColor: current.configuration?.usesCIEColor ?? false,
      mediaSelection: current.configuration?.mediaSelection ?? .virtual,
      placement: current.configuration?.placement ?? .simplex,
      delivery: current.configuration?.delivery ?? .virtual
    )
  }

  func incrementPageNumber() {
    state.withLock { $0.pageNumber += 1 }
  }

  func resetPageNumber() {
    state.withLock { $0.pageNumber = 0 }
  }

  func transmission(
    trigger: GraphicsPageTransmissionTrigger,
    copies: Int
  ) -> GraphicsPageTransmission {
    state.withLock { current in
      let configuration = current.configuration
      return GraphicsPageTransmission(
        trigger: trigger,
        logicalOrdinal: current.logicalTransmissionOrdinal + 1,
        copies: copies,
        mediaSelection: configuration?.mediaSelection ?? .virtual,
        placement: configuration?.placement ?? .simplex,
        delivery: configuration?.delivery ?? .virtual
      )
    }
  }

  func commitTransmission(copies: Int) {
    state.withLock { current in
      current.logicalTransmissionOrdinal += 1
      guard copies > 0, var configuration = current.configuration else { return }
      let placement = configuration.placement
      let insertSheet = configuration.mediaRequest.attributes.insertsSheet == true
      let deliveredSides = configuration.delivery.collates ? 1 : copies
      let nextSide: GraphicsSheetSide
      if insertSheet || !placement.isDuplex {
        nextSide = .recto
      } else if deliveredSides.isMultiple(of: 2) {
        nextSide = placement.side
      } else {
        nextSide = placement.side == .recto ? .verso : .recto
      }
      let nextPlacement = placement.replacing(side: nextSide)
      let resolution = GraphicsSize(
        width: configuration.descriptor.horizontalResolution,
        height: configuration.descriptor.verticalResolution
      )
      let mediaSize = GraphicsSize(
        width: configuration.descriptor.mediaBounds.width * 72 / resolution.width,
        height: configuration.descriptor.mediaBounds.height * 72 / resolution.height
      )
      let currentTransform = placement.transform(for: mediaSize)
      let baseMatrix = currentTransform.inverted?.concatenated(
        with: configuration.descriptor.defaultMatrix
      ) ?? configuration.descriptor.defaultMatrix
      let descriptor = configuration.descriptor.replacing(
        defaultMatrix: nextPlacement.transform(for: mediaSize).concatenated(with: baseMatrix)
      )
      configuration = configuration.replacing(placement: nextPlacement, descriptor: descriptor)
      current.configuration = configuration
    }
  }

  func updateConfiguration(_ configuration: GraphicsPageDeviceConfiguration) {
    state.withLock { $0.configuration = configuration }
  }

  var trapping: GraphicsTrappingSnapshot {
    state.withLock { $0.trapping }
  }

  var trapSetNameSource: Object? {
    state.withLock { $0.trapSetNameSource }
  }

  func updateTrapping(_ trapping: GraphicsTrappingSnapshot, trapSetNameSource: Object?) {
    state.withLock {
      $0.trapping = trapping
      $0.trapSetNameSource = trapSetNameSource
    }
  }

  func captureDefaultTrappingZones() {
    state.withLock { $0.defaultTrappingZones = $0.trapping.zones }
  }

  func restoreDefaultTrappingZones() {
    state.withLock {
      $0.trapping = GraphicsTrappingSnapshot(
        enabled: $0.trapping.enabled,
        details: $0.trapping.details,
        parameters: $0.trapping.parameters,
        zones: $0.defaultTrappingZones
      )
    }
  }

  func discardPageTrappingZones() {
    state.withLock {
      $0.trapping = GraphicsTrappingSnapshot(
        enabled: $0.trapping.enabled,
        details: $0.trapping.details,
        parameters: $0.trapping.parameters,
        zones: []
      )
      $0.defaultTrappingZones = []
    }
  }

  func savedTrappingState() -> PostScriptDeviceTrappingState {
    state.withLock {
      PostScriptDeviceTrappingState(
        configuration: $0.configuration,
        pageNumber: $0.pageNumber,
        logicalTransmissionOrdinal: $0.logicalTransmissionOrdinal,
        snapshot: $0.trapping,
        defaultZones: $0.defaultTrappingZones,
        trapSetNameSource: $0.trapSetNameSource
      )
    }
  }

  func restoreTrappingState(_ saved: PostScriptDeviceTrappingState) {
    state.withLock {
      $0.configuration = saved.configuration
      $0.pageNumber = saved.pageNumber
      $0.logicalTransmissionOrdinal = saved.logicalTransmissionOrdinal
      $0.trapping = saved.snapshot
      $0.defaultTrappingZones = saved.defaultZones
      $0.trapSetNameSource = saved.trapSetNameSource
    }
  }

  static func page(descriptor: GraphicsDeviceDescriptor) -> PostScriptDeviceRecord {
    let pageSize = GraphicsSize(
      width: descriptor.mediaBounds.width * 72 / descriptor.horizontalResolution,
      height: descriptor.mediaBounds.height * 72 / descriptor.verticalResolution
    )
    return PostScriptDeviceRecord(configuration: GraphicsPageDeviceConfiguration(
      identifier: GraphicsDeviceIdentifier(),
      pageSize: pageSize,
      imagingBoundingBox: nil,
      numberOfCopies: 1,
      name: "SolidVirtualPageDevice",
      descriptor: descriptor,
      colorants: descriptor.colorants
    ))
  }

  static func null() -> PostScriptDeviceRecord {
    let origin = GraphicsRect(x: 0, y: 0, width: 0, height: 0)
    return PostScriptDeviceRecord(nullDescriptor: GraphicsDeviceDescriptor(
      mediaBounds: GraphicsRect(x: 0, y: 0, width: 1, height: 1),
      imageableBounds: origin,
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    ))
  }
}

extension GraphicsPageDeviceConfiguration {
  func replacing(
    placement: GraphicsPagePlacement,
    descriptor: GraphicsDeviceDescriptor
  ) -> Self {
    Self(
      identifier: identifier,
      pageSize: pageSize,
      imagingBoundingBox: imagingBoundingBox,
      numberOfCopies: numberOfCopies,
      name: name,
      descriptor: descriptor,
      colorants: colorants,
      trappingEnabled: trappingEnabled,
      trappingDetails: trappingDetails,
      usesCIEColor: usesCIEColor,
      outputDeviceIdentifier: outputDeviceIdentifier,
      outputDevice: outputDevice,
      inputMedia: inputMedia,
      mediaRequest: mediaRequest,
      mediaSelection: mediaSelection,
      outputDestinations: outputDestinations,
      outputType: outputType,
      placement: placement,
      delivery: delivery
    )
  }
}
