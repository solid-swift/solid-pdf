import Foundation

/// The portable output of a recording graphics target.
public struct GraphicsRecording: Sendable, Hashable {
  /// The pages explicitly transmitted with `showpage`.
  public let pages: [RecordedGraphicsPage]

  /// Creates a recording.
  public init(pages: [RecordedGraphicsPage]) {
    self.pages = pages
  }
}
