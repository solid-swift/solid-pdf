import Foundation

/// A device-pixel spot screen compiled from a PostScript spot function.
public struct GraphicsSpotScreen: Sendable, Hashable {
  public let frequency: Double
  public let angle: Double
  public let actualFrequency: Double
  public let actualAngle: Double
  public let width: Int
  public let height: Int
  /// Thresholds in row-major order, where zero has already been normalized to one.
  public let thresholds: [UInt16]

  /// Creates a compiled spot screen.
  public init(
    frequency: Double,
    angle: Double,
    actualFrequency: Double,
    actualAngle: Double,
    width: Int,
    height: Int,
    thresholds: [UInt16]
  ) throws {
    let count = width.multipliedReportingOverflow(by: height)
    guard frequency > 0, frequency.isFinite, angle.isFinite,
      actualFrequency > 0, actualFrequency.isFinite, actualAngle.isFinite,
      width > 0, height > 0, !count.overflow, count.partialValue == thresholds.count
    else { throw Error.rangeCheck }
    self.frequency = frequency
    self.angle = angle
    self.actualFrequency = actualFrequency
    self.actualAngle = actualAngle
    self.width = width
    self.height = height
    self.thresholds = thresholds.map { max(1, $0) }
  }
}
