import Foundation
import SolidColor

enum GraphicsColorantResolver {
  static func resolve(
    _ paint: GraphicsPaint,
    configuration: GraphicsColorantConfiguration
  ) throws -> GraphicsColorantPaint {
    switch paint {
    case .deviceGray(let gray):
      return try process(
        rgb: ColorRGB(red: gray, green: gray, blue: gray),
        configuration: configuration,
        preview: paint
      )
    case .deviceRGB(let red, let green, let blue):
      return try process(
        rgb: ColorRGB(red: red, green: green, blue: blue),
        configuration: configuration,
        preview: paint
      )
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      if configuration.processModel == .deviceCMYK {
        return result(
          [("Cyan", cyan), ("Magenta", magenta), ("Yellow", yellow), ("Black", black)],
          preview: paint
        )
      }
      return try process(
        rgb: ColorCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black).rgb,
        configuration: configuration,
        preview: paint
      )
    case .color(let value):
      return try resolve(value, configuration: configuration)
    case .pattern:
      throw Error.ioError
    }
  }

  private static func resolve(
    _ value: GraphicsColorValue,
    configuration: GraphicsColorantConfiguration
  ) throws -> GraphicsColorantPaint {
    switch value {
    case .deviceGray(let gray):
      return try process(
        rgb: ColorRGB(red: gray, green: gray, blue: gray),
        configuration: configuration,
        preview: .color(value)
      )
    case .deviceRGB(let rgb):
      return try process(rgb: rgb, configuration: configuration, preview: .color(value))
    case .deviceCMYK(let cmyk):
      return try resolve(
        .deviceCMYK(cyan: cmyk.cyan, magenta: cmyk.magenta, yellow: cmyk.yellow, black: cmyk.black),
        configuration: configuration
      )
    case .cie(_, _, _, let device):
      guard let device else { throw Error.ioError }
      return try resolve(device, configuration: configuration)
    case .named(_, _, _, let alternative):
      return try resolve(alternative, configuration: configuration)
    case .directColorants(_, let names, let tints):
      if names == ["None"] {
        return GraphicsColorantPaint(components: [], paintsNothing: true, preview: .color(value))
      }
      if names == ["All"] {
        let tint = tints.first ?? 0
        return GraphicsColorantPaint(
          components: configuration.availableColorants.map {
            GraphicsColorantComponent(name: $0.name, tint: tint)
          },
          addressesAllColorants: true,
          preview: .color(value)
        )
      }
      return result(Array(zip(names, tints)), preview: .color(value))
    }
  }

  private static func process(
    rgb: ColorRGB,
    configuration: GraphicsColorantConfiguration,
    preview: GraphicsPaint
  ) throws -> GraphicsColorantPaint {
    let rgb = rgb.clamped
    switch configuration.processModel {
    case .deviceGray:
      return result([("Gray", 1 - (0.3 * rgb.red + 0.59 * rgb.green + 0.11 * rgb.blue))], preview: preview)
    case .deviceRGB:
      return result([("Red", 1 - rgb.red), ("Green", 1 - rgb.green), ("Blue", 1 - rgb.blue)], preview: preview)
    case .deviceCMY:
      return result([("Cyan", 1 - rgb.red), ("Magenta", 1 - rgb.green), ("Yellow", 1 - rgb.blue)], preview: preview)
    case .deviceCMYK:
      let cyan = 1 - rgb.red
      let magenta = 1 - rgb.green
      let yellow = 1 - rgb.blue
      let black = min(cyan, magenta, yellow)
      return result([
        ("Cyan", cyan - black),
        ("Magenta", magenta - black),
        ("Yellow", yellow - black),
        ("Black", black),
      ], preview: preview)
    case .deviceRGBK:
      if rgb.red == rgb.green, rgb.green == rgb.blue {
        return result([("Red", 0), ("Green", 0), ("Blue", 0), ("Gray", 1 - rgb.red)], preview: preview)
      }
      return result([
        ("Red", 1 - rgb.red), ("Green", 1 - rgb.green), ("Blue", 1 - rgb.blue), ("Gray", 0),
      ], preview: preview)
    case .deviceN:
      guard configuration.hasUsableDeviceNLookup, let lookup = configuration.rgbToDeviceN else {
        throw Error.configurationError
      }
      let values: [Double]
      do {
        values = try lookup.interpolate([rgb.red, rgb.green, rgb.blue])
      } catch {
        throw Error.configurationError
      }
      let names = configuration.additionalColorants.filter(\.isProcessColorant).map(\.name)
      return result(Array(zip(names, values)), preview: preview)
    }
  }

  private static func result(
    _ values: [(String, Double)],
    preview: GraphicsPaint
  ) -> GraphicsColorantPaint {
    GraphicsColorantPaint(
      components: values.map { GraphicsColorantComponent(name: $0.0, tint: $0.1) },
      preview: preview
    )
  }
}
