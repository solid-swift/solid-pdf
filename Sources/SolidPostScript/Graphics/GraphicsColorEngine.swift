import Foundation

/// Creates a target-specific color conversion session for one render.
public protocol GraphicsColorEngine<Session>: Sendable {
  associatedtype Session: GraphicsColorSession

  /// Creates isolated color conversion state for `device`.
  func makeSession(for device: GraphicsDeviceDescriptor) throws -> sending Session
}

/// Resolves portable paints and creates target-specific sampled-image converters.
public protocol GraphicsColorSession<ResolvedPaint, ImageConverter>: AnyObject {
  associatedtype ResolvedPaint: Sendable
  associatedtype ImageConverter: GraphicsColorImageConverter

  /// Resolves a portable paint for the session's destination.
  func resolve(_ paint: GraphicsPaint) throws -> ResolvedPaint
  /// Creates an ordered converter for one sampled-image transfer.
  func makeImageConverter(for descriptor: GraphicsImageDescriptor) throws -> sending ImageConverter
}

/// Converts one ordered sampled-image transfer into a target-specific image.
public protocol GraphicsColorImageConverter<ResolvedImage>: AnyObject {
  associatedtype ResolvedImage: Sendable

  /// Consumes a bounded group of complete source rows.
  func write(_ rows: GraphicsImageRows) throws
  /// Completes conversion and returns the immutable image.
  func finish() throws -> sending ResolvedImage
  /// Abandons conversion without producing an image.
  func abort()
}

/// The compatibility color engine that preserves portable graphics values unchanged.
public struct SemanticGraphicsColorEngine: GraphicsColorEngine, Sendable {
  /// Creates a semantic engine.
  public init() {}

  /// Creates one semantic color session.
  public func makeSession(for device: GraphicsDeviceDescriptor) -> sending SemanticGraphicsColorSession {
    SemanticGraphicsColorSession()
  }
}

/// A color session used by recording, null, and compatibility targets.
public final class SemanticGraphicsColorSession: GraphicsColorSession {
  /// Creates a semantic session.
  public init() {}

  /// Returns the portable paint unchanged.
  public func resolve(_ paint: GraphicsPaint) -> GraphicsPaint { paint }

  /// Creates a converter that retains portable image samples.
  public func makeImageConverter(
    for descriptor: GraphicsImageDescriptor
  ) -> sending SemanticGraphicsColorImageConverter {
    SemanticGraphicsColorImageConverter(descriptor: descriptor)
  }
}

/// A sampled-image converter that records normalized components without device conversion.
public final class SemanticGraphicsColorImageConverter: GraphicsColorImageConverter {
  private let descriptor: GraphicsImageDescriptor
  private var components: [Float] = []
  private var nextRow = 0
  private var aborted = false

  /// Creates a converter for `descriptor`.
  public init(descriptor: GraphicsImageDescriptor) {
    self.descriptor = descriptor
  }

  /// Retains an ordered group of source rows.
  public func write(_ rows: GraphicsImageRows) throws {
    let expected = rows.rowCount * descriptor.width * descriptor.kind.componentCount
    guard !aborted, rows.startRow == nextRow, rows.components.count == expected else { throw Error.ioError }
    components.append(contentsOf: rows.components)
    nextRow += rows.rowCount
  }

  /// Returns the completed portable image.
  public func finish() throws -> sending GraphicsImage {
    guard !aborted else { throw Error.ioError }
    return GraphicsImage(descriptor: descriptor, components: components)
  }

  /// Abandons retained samples.
  public func abort() {
    aborted = true
    components.removeAll()
  }
}
