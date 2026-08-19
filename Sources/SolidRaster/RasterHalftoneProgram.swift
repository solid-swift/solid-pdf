import Foundation

/// A rectangular threshold screen evaluated in absolute device-pixel coordinates.
public struct RasterThresholdScreen: Sendable, Hashable {
  public let width: Int
  public let height: Int
  public let maximumThreshold: UInt16
  public let thresholds: [UInt16]

  /// Creates a threshold screen.
  public init(
    width: Int,
    height: Int,
    maximumThreshold: UInt16,
    thresholds: [UInt16]
  ) throws(RasterError) {
    let count = width.multipliedReportingOverflow(by: height)
    guard width > 0, height > 0, maximumThreshold > 0,
      !count.overflow, count.partialValue == thresholds.count
    else { throw .invalidGeometry }
    self.width = width
    self.height = height
    self.maximumThreshold = maximumThreshold
    self.thresholds = thresholds.map { max(1, $0) }
  }

  /// Returns the normalized threshold at an absolute device pixel.
  public func threshold(x: Int, y: Int) -> Double {
    let column = positiveRemainder(x, divisor: width)
    let row = positiveRemainder(y, divisor: height)
    return Double(thresholds[row * width + column]) / Double(maximumThreshold)
  }

  private func positiveRemainder(_ value: Int, divisor: Int) -> Int {
    let remainder = value % divisor
    return remainder < 0 ? remainder + divisor : remainder
  }
}

/// A portable raster program for component transfer and spatial quantization.
public struct RasterHalftoneProgram: Sendable, Hashable {
  public let redTransfer: [Double]
  public let greenTransfer: [Double]
  public let blueTransfer: [Double]
  public let grayTransfer: [Double]
  public let componentLevels: [Int]?
  public let defaultScreen: RasterThresholdScreen?
  public let colorantScreens: [String: RasterThresholdScreen]

  /// Creates a raster device-rendering program.
  public init(
    redTransfer: [Double] = [0, 1],
    greenTransfer: [Double] = [0, 1],
    blueTransfer: [Double] = [0, 1],
    grayTransfer: [Double] = [0, 1],
    componentLevels: [Int]? = nil,
    defaultScreen: RasterThresholdScreen? = nil,
    colorantScreens: [String: RasterThresholdScreen] = [:]
  ) throws(RasterError) {
    let tables = [redTransfer, greenTransfer, blueTransfer, grayTransfer]
    guard tables.allSatisfy({ $0.count >= 2 && $0.allSatisfy(\.isFinite) }),
      componentLevels?.allSatisfy({ $0 >= 2 }) != false
    else { throw .invalidGeometry }
    self.redTransfer = redTransfer
    self.greenTransfer = greenTransfer
    self.blueTransfer = blueTransfer
    self.grayTransfer = grayTransfer
    self.componentLevels = componentLevels
    self.defaultScreen = defaultScreen
    self.colorantScreens = colorantScreens
  }

  /// Identity continuous-tone rendering.
  public static let continuousTone = try! Self()
}
