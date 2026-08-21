import SolidPostScript
import SolidRaster

extension Interpreter {
  /// Renders PostScript content through the default native raster target.
  public static func render(content: String) async throws -> GraphicsRenderResult<[RasterImage]> {
    try await render(content: content, to: RasterImageTarget())
  }

  /// Renders PostScript content through the default native raster target in `environment`.
  public static func render(
    content: String,
    environment: InterpreterEnvironment
  ) async throws -> GraphicsRenderResult<[RasterImage]> {
    try await render(content: content, to: RasterImageTarget(), environment: environment)
  }

  /// Renders a PostScript file through the default native raster target.
  public static func render(file: File) async throws -> GraphicsRenderResult<[RasterImage]> {
    try await render(file: file, to: RasterImageTarget())
  }

  /// Renders a PostScript file through the default native raster target in `environment`.
  public static func render(
    file: File,
    environment: InterpreterEnvironment
  ) async throws -> GraphicsRenderResult<[RasterImage]> {
    try await render(file: file, to: RasterImageTarget(), environment: environment)
  }
}
