/// Tracks retained page and image storage for one built-in renderer.
package final class GraphicsStorageTracker {
  private var session: GraphicsStorageAccountingSession?
  private var currentDisplay: GraphicsStorageReservation?
  private var currentSource: GraphicsStorageReservation?
  private var activeImage: GraphicsStorageReservation?
  private var retained: [GraphicsStorageReservation] = []
  private var pendingError: GraphicsStorageAccountingError?

  package init() {}

  package func install(_ session: GraphicsStorageAccountingSession) {
    self.session = session
  }

  package func updateCurrent(effects: [GraphicsEffect]) throws {
    guard let session else { return }
    guard let footprint = GraphicsDisplayList(effects: effects).storageFootprint(),
      footprint.displayBytes != .max,
      footprint.sourceBytes != .max
    else { throw GraphicsStorageAccountingError.limitExceeded }
    currentDisplay = try resize(
      currentDisplay,
      kind: .displayList,
      bytes: footprint.displayBytes,
      session: session
    )
    currentSource = try resize(
      currentSource,
      kind: .sourceList,
      bytes: footprint.sourceBytes,
      session: session
    )
  }

  package func updateCurrentDeferringError(effects: [GraphicsEffect]) -> Bool {
    do {
      try updateCurrent(effects: effects)
      return true
    } catch let error as GraphicsStorageAccountingError {
      pendingError = error
      return false
    } catch {
      pendingError = .limitExceeded
      return false
    }
  }

  package func takeError() -> GraphicsStorageAccountingError? {
    defer { pendingError = nil }
    return pendingError
  }

  package func beginImage() throws {
    guard let session else { return }
    activeImage = try session.reserve(.imageBuffer, bytes: 0)
  }

  package func resizeImage(to bytes: Int) throws {
    try activeImage?.resize(to: bytes)
  }

  package func endImage(effects: [GraphicsEffect]) throws {
    activeImage?.release()
    activeImage = nil
    try updateCurrent(effects: effects)
  }

  package func abortImage() {
    activeImage?.release()
    activeImage = nil
  }

  package func transmit(retainingPage: Bool) {
    if retainingPage {
      if let currentDisplay { retained.append(currentDisplay) }
      if let currentSource { retained.append(currentSource) }
    } else {
      currentDisplay?.release()
      currentSource?.release()
    }
    currentDisplay = nil
    currentSource = nil
  }

  package func clearCurrent() {
    abortImage()
    currentDisplay?.release()
    currentSource?.release()
    currentDisplay = nil
    currentSource = nil
  }

  package func releaseAll() {
    clearCurrent()
    retained.forEach { $0.release() }
    retained.removeAll()
    pendingError = nil
  }

  private func resize(
    _ reservation: GraphicsStorageReservation?,
    kind: GraphicsRetainedStorageKind,
    bytes: Int,
    session: GraphicsStorageAccountingSession
  ) throws -> GraphicsStorageReservation? {
    if bytes == 0 {
      reservation?.release()
      return nil
    }
    if let reservation {
      try reservation.resize(to: bytes)
      return reservation
    }
    return try session.reserve(kind, bytes: bytes)
  }
}
