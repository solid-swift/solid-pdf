import Foundation
import Synchronization

final class PostScriptDeviceRecord: Sendable {
  struct State: Sendable {
    var configuration: GraphicsPageDeviceConfiguration?
    var pageNumber: Int
  }

  let identifier: GraphicsDeviceIdentifier
  let kind: GraphicsDeviceKind
  private let state: Mutex<State>

  init(configuration: GraphicsPageDeviceConfiguration) {
    self.identifier = configuration.identifier
    self.kind = .page
    self.state = Mutex(State(configuration: configuration, pageNumber: 0))
    self.nullDescriptor = nil
  }

  init(nullDescriptor descriptor: GraphicsDeviceDescriptor) {
    self.identifier = GraphicsDeviceIdentifier()
    self.kind = .null
    self.state = Mutex(State(configuration: nil, pageNumber: 0))
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
      numberOfCopies: current.configuration?.numberOfCopies
    )
  }

  func incrementPageNumber() {
    state.withLock { $0.pageNumber += 1 }
  }

  func resetPageNumber() {
    state.withLock { $0.pageNumber = 0 }
  }

  func updateConfiguration(_ configuration: GraphicsPageDeviceConfiguration) {
    state.withLock { $0.configuration = configuration }
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
      descriptor: descriptor
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
