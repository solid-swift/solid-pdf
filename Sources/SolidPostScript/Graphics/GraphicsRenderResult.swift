import Foundation

/// The completed interpreter context and typed graphics output of a render.
public struct GraphicsRenderResult<Output> {
  /// The completed PostScript context.
  public let context: Context
  /// The target-specific completed output.
  public let output: Output

  /// Creates a render result.
  public init(context: Context, output: Output) {
    self.context = context
    self.output = output
  }
}

extension GraphicsRenderResult: Sendable where Output: Sendable {}
