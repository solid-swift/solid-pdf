import Foundation

/// A page device's native process-color model.
public enum GraphicsProcessColorModel: String, Sendable, Hashable, CaseIterable {
  case deviceGray = "DeviceGray"
  case deviceRGB = "DeviceRGB"
  case deviceCMYK = "DeviceCMYK"
  case deviceCMY = "DeviceCMY"
  case deviceRGBK = "DeviceRGBK"
  case deviceN = "DeviceN"

  /// Process colorants implied by the model.
  public var colorantNames: [String] {
    switch self {
    case .deviceGray: ["Gray"]
    case .deviceRGB: ["Red", "Green", "Blue"]
    case .deviceCMYK: ["Cyan", "Magenta", "Yellow", "Black"]
    case .deviceCMY: ["Cyan", "Magenta", "Yellow"]
    case .deviceRGBK: ["Red", "Green", "Blue", "Gray"]
    case .deviceN: []
    }
  }
}
