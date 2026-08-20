/// Creates a mutable sink session for one raster render.
public protocol RasterPageSink<Session>: Sendable {
  associatedtype Session: RasterPageSinkSession

  /// Creates an isolated session.
  func makeSession() throws -> sending Session
}

/// Incrementally consumes transmitted raster pages and produces typed output.
public protocol RasterPageSinkSession<Output>: AnyObject {
  associatedtype Output

  /// Consumes one transferred page in transmission order.
  func consume(_ page: RasterRenderedPage) throws
  /// Completes the sink after successful PostScript execution.
  func finish() throws -> sending Output
  /// Abandons all staged sink output.
  func abort()
}
