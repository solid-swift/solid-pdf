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
  /// Resolves a bounded batch of portable paints in order.
  func resolve(_ paints: [GraphicsPaint]) throws -> [ResolvedPaint]
  /// Resolves a portable paint after applying device-rendering controls.
  func resolve(
    _ paint: GraphicsPaint,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> ResolvedPaint
  /// Resolves a bounded batch after applying device-rendering controls.
  func resolve(
    _ paints: [GraphicsPaint],
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> [ResolvedPaint]
  /// Creates an ordered converter for one sampled-image transfer.
  func makeImageConverter(for descriptor: GraphicsImageDescriptor) throws -> sending ImageConverter
  /// Creates an image converter that applies the captured device-rendering controls.
  func makeImageConverter(
    for descriptor: GraphicsImageDescriptor,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> sending ImageConverter
}

extension GraphicsColorSession {
  /// Resolves a batch by applying the scalar resolver in order.
  public func resolve(_ paints: [GraphicsPaint]) throws -> [ResolvedPaint] {
    try paints.map(resolve)
  }

  /// Preserves source compatibility for engines that do not implement device rendering.
  public func resolve(
    _ paint: GraphicsPaint,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> ResolvedPaint {
    try resolve(paint)
  }

  /// Preserves source compatibility for engines that do not implement device rendering.
  public func resolve(
    _ paints: [GraphicsPaint],
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> [ResolvedPaint] {
    try resolve(paints)
  }

  /// Preserves source compatibility for engines that do not implement device rendering.
  public func makeImageConverter(
    for descriptor: GraphicsImageDescriptor,
    deviceRendering: GraphicsDeviceRenderingSnapshot
  ) throws -> sending ImageConverter {
    try makeImageConverter(for: descriptor)
  }
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
  private var sourceComponents: [Float] = []
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
    if let source = rows.sourceComponents {
      sourceComponents.append(contentsOf: source)
    }
    nextRow += rows.rowCount
  }

  /// Returns the completed portable image.
  public func finish() throws -> sending GraphicsImage {
    guard !aborted else { throw Error.ioError }
    return GraphicsImage(
      descriptor: descriptor,
      components: components,
      sourceComponents: sourceComponents.isEmpty ? nil : sourceComponents
    )
  }

  /// Abandons retained samples.
  public func abort() {
    aborted = true
    components.removeAll()
    sourceComponents.removeAll()
  }
}
