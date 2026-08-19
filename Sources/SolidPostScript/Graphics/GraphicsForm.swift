import Foundation

/// An immutable, reusable Type 1 PostScript form compiled for a graphics device and state.
public struct GraphicsForm: Sendable, Hashable {
  /// The form's bounding box in form space.
  public let bounds: GraphicsRect
  /// The matrix mapping form space into the user space active at invocation.
  public let matrix: GraphicsMatrix
  /// The device for which the display list was compiled.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The graphics state established while the display list was compiled.
  public let compilationState: GraphicsStateSnapshot
  /// The realized effects produced by the form's paint procedure.
  public let displayList: GraphicsDisplayList

  /// Creates a compiled Type 1 form.
  public init(
    bounds: GraphicsRect,
    matrix: GraphicsMatrix,
    deviceDescriptor: GraphicsDeviceDescriptor,
    compilationState: GraphicsStateSnapshot,
    displayList: GraphicsDisplayList
  ) {
    self.bounds = bounds
    self.matrix = matrix
    self.deviceDescriptor = deviceDescriptor
    self.compilationState = compilationState
    self.displayList = displayList
  }
}
