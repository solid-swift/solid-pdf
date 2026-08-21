import Foundation

enum PostScriptDeviceColorProjection: Sendable, Hashable {
  case gray(Double)
  case rgb(red: Double, green: Double, blue: Double)
  case cmyk(cyan: Double, magenta: Double, yellow: Double, black: Double)

  var paint: GraphicsPaint {
    switch self {
    case .gray(let gray):
      .deviceGray(gray)
    case .rgb(let red, let green, let blue):
      .deviceRGB(red: red, green: green, blue: blue)
    case .cmyk(let cyan, let magenta, let yellow, let black):
      .deviceCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black)
    }
  }
}
