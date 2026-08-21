import Foundation
import Synchronization

/// A stable key that may correlate equivalent graphics resources across instances.
public struct GraphicsResourceStableKey: Sendable, Hashable {
  /// The namespace defining the key's interpretation, such as `XUID` or `SHA256`.
  public let namespace: String
  /// The namespace-specific key bytes.
  public let value: Data

  /// Creates a stable graphics-resource key.
  public init(namespace: String, value: Data) {
    self.namespace = namespace
    self.value = value
  }

  static func xuid(_ values: [Int32]) -> Self {
    var data = Data(capacity: values.count * MemoryLayout<Int32>.size)
    for value in values {
      var bigEndian = value.bigEndian
      withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    return Self(namespace: "XUID", value: data)
  }
}

/// An opaque identity for an immutable graphics resource.
///
/// Identities are meaningful only within the interpreter environment that produced them. The
/// optional stable key may be used to correlate equivalent resources across independent instances.
public struct GraphicsResourceIdentifier: Sendable, Hashable {
  /// The opaque environment-scoped value.
  public let rawValue: String
  /// An optional installation-independent correlation key.
  public let stableKey: GraphicsResourceStableKey?

  /// Creates a resource identifier for a custom graphics producer.
  public init(rawValue: String, stableKey: GraphicsResourceStableKey? = nil) {
    self.rawValue = rawValue
    self.stableKey = stableKey
  }

  /// An anonymous resource emitted by a source-compatible producer without identity support.
  public static let anonymous = Self(rawValue: "")

  /// Whether this identifier can correlate repeated resource references.
  public var isAnonymous: Bool { rawValue.isEmpty }
}

final class GraphicsResourceIdentityAllocator: Sendable {
  private let namespace = UUID().uuidString
  private let nextValue = Mutex<UInt64>(0)

  func next(stableKey: GraphicsResourceStableKey? = nil) -> GraphicsResourceIdentifier {
    let value = nextValue.withLock { value -> UInt64 in
      value &+= 1
      return value
    }
    return GraphicsResourceIdentifier(rawValue: "\(namespace):\(value)", stableKey: stableKey)
  }
}
