import Foundation

/// A rectangular threshold screen evaluated in absolute device-pixel coordinates.
public struct RasterThresholdScreen: Sendable, Hashable {
  public let width: Int
  public let height: Int
  public let maximumThreshold: UInt16
  public let thresholds: [UInt16]
  public let secondaryWidth: Int?
  public let secondaryHeight: Int?

  /// Creates a threshold screen.
  public init(
    width: Int,
    height: Int,
    maximumThreshold: UInt16,
    thresholds: [UInt16],
    secondaryWidth: Int? = nil,
    secondaryHeight: Int? = nil
  ) throws(RasterError) {
    let primary = width.multipliedReportingOverflow(by: height)
    let secondary: (partialValue: Int, overflow: Bool)
    if let secondaryWidth, let secondaryHeight {
      secondary = secondaryWidth.multipliedReportingOverflow(by: secondaryHeight)
    } else {
      secondary = (0, secondaryWidth != nil || secondaryHeight != nil)
    }
    let count = primary.partialValue.addingReportingOverflow(secondary.partialValue)
    guard width > 0, height > 0, maximumThreshold > 0,
      !primary.overflow, !secondary.overflow, !count.overflow,
      count.partialValue == thresholds.count
    else { throw .invalidGeometry }
    self.width = width
    self.height = height
    self.maximumThreshold = maximumThreshold
    self.thresholds = thresholds.map { max(1, $0) }
    self.secondaryWidth = secondaryWidth
    self.secondaryHeight = secondaryHeight
  }

  /// Returns the normalized threshold at an absolute device pixel.
  public func threshold(x: Int, y: Int) -> Double {
    if let secondaryWidth, let secondaryHeight {
      let totalHeight = height + secondaryHeight
      let row = positiveRemainder(y, divisor: totalHeight)
      if row >= height {
        let column = positiveRemainder(x, divisor: secondaryWidth)
        let index = width * height + (row - height) * secondaryWidth + column
        return Double(thresholds[index]) / Double(maximumThreshold)
      }
    }
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

  /// Applies spatial component quantization at one absolute device pixel.
  public func quantize(_ source: SIMD4<UInt16>, x: Int, y: Int) -> SIMD4<UInt16> {
    guard let componentLevels, !componentLevels.isEmpty, source[3] > 0 else { return source }
    let alpha = source[3]
    var result = source
    let names = ["Red", "Green", "Blue"]
    for component in 0..<3 {
      let levelIndex = min(component, componentLevels.count - 1)
      let levels = componentLevels[levelIndex]
      let normalized = min(1, max(0, Double(source[component]) / Double(alpha)))
      let scaled = normalized * Double(levels - 1)
      let lower = Int(scaled.rounded(.down))
      let fraction = scaled - Double(lower)
      let screen = colorantScreens[names[component]]
        ?? colorantScreens["Default"]
        ?? defaultScreen
      let raised = screen.map { fraction >= $0.threshold(x: x, y: y) } ?? (fraction >= 0.5)
      let quantized = min(levels - 1, lower + (raised ? 1 : 0))
      result[component] = UInt16(
        (Double(quantized) / Double(levels - 1) * Double(alpha)).rounded()
      )
    }
    return result
  }
}
