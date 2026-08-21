import Foundation

/// One physical sheet containing an optional front and back side.
public struct GraphicsPrintSheet: Sendable, Hashable {
  /// The sheet's zero-based physical delivery index.
  public let index: Int
  /// The recto side.
  public let front: GraphicsPrintSide?
  /// The verso side.
  public let back: GraphicsPrintSide?
  /// The input medium used for the sheet.
  public let mediaSelection: GraphicsMediaSelection
  /// The selected output destination.
  public let destination: GraphicsOutputDestination?
  /// The stacking direction selected for this sheet.
  public let outputFace: GraphicsOutputFace

  /// Creates a physical print sheet.
  public init(
    index: Int,
    front: GraphicsPrintSide?,
    back: GraphicsPrintSide?,
    mediaSelection: GraphicsMediaSelection,
    destination: GraphicsOutputDestination?,
    outputFace: GraphicsOutputFace
  ) {
    self.index = index
    self.front = front
    self.back = back
    self.mediaSelection = mediaSelection
    self.destination = destination
    self.outputFace = outputFace
  }
}
