import Foundation
import Synchronization

final class FormInitializationRegistry: Sendable {
  private let implementations = Mutex<[ObjectIdentifier: ObjectIdentifier]>([:])

  func contains(form: ObjectIdentifier, implementation: ObjectIdentifier) -> Bool {
    implementations.withLock { $0[form] == implementation }
  }

  func register(form: ObjectIdentifier, implementation: ObjectIdentifier) {
    implementations.withLock { $0[form] = implementation }
  }
}
