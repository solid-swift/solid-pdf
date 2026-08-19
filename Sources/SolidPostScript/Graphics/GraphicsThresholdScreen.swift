import Foundation

/// A rectangular threshold screen in absolute device-pixel coordinates.
public struct GraphicsThresholdScreen: Sendable, Hashable {
  public let width: Int
  public let height: Int
  public let bitsPerSample: Int
  public let thresholds: [UInt16]
  public let secondaryWidth: Int?
  public let secondaryHeight: Int?
  public let usesAngledSquares: Bool
  /// A component transfer function overriding the graphics-state transfer, if present.
  public let transferFunction: GraphicsComponentFunction?

  /// Creates a threshold screen.
  public init(
    width: Int,
    height: Int,
    bitsPerSample: Int = 8,
    thresholds: [UInt16],
    secondaryWidth: Int? = nil,
    secondaryHeight: Int? = nil,
    usesAngledSquares: Bool = false,
    transferFunction: GraphicsComponentFunction? = nil
  ) throws {
    let primary = width.multipliedReportingOverflow(by: height)
    let secondary: (partialValue: Int, overflow: Bool)
    if let secondaryWidth, let secondaryHeight {
      secondary = secondaryWidth.multipliedReportingOverflow(by: secondaryHeight)
    } else {
      secondary = (0, secondaryWidth != nil || secondaryHeight != nil)
    }
    let count = primary.partialValue.addingReportingOverflow(secondary.partialValue)
    guard width > 0, height > 0, bitsPerSample == 8 || bitsPerSample == 16,
      secondaryWidth.map({ $0 > 0 }) ?? true,
      secondaryHeight.map({ $0 > 0 }) ?? true,
      !primary.overflow, !secondary.overflow, !count.overflow,
      count.partialValue == thresholds.count
    else { throw Error.rangeCheck }
    self.width = width
    self.height = height
    self.bitsPerSample = bitsPerSample
    self.thresholds = thresholds.map { max(1, $0) }
    self.secondaryWidth = secondaryWidth
    self.secondaryHeight = secondaryHeight
    self.usesAngledSquares = usesAngledSquares
    self.transferFunction = transferFunction
  }
}
