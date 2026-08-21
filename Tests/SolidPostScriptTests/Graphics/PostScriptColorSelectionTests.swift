import Testing

@testable import SolidPostScript

@Suite
struct PostScriptColorSelectionTests {
  @Test func namedColorantDispositionIsSelectedOnce() throws {
    let source = try Object.array([], access: .unlimited, vm: .local, kind: .literal)
    let transform = try Object.array([], access: .unlimited, vm: .local, kind: .executable)
    let colorSpace = PostScriptColorSpace.separation(
      source: source,
      name: "Spot",
      alternative: .deviceRGB(nil),
      transform: transform
    )

    let direct = PostScriptColorSelection.direct(colorSpace, availableColorants: ["Spot"])
    guard case .directColorants(_, let directNames) = direct.route else {
      Issue.record("Expected a direct named-color route")
      return
    }
    #expect(directNames == ["Spot"])

    let alternative = PostScriptColorSelection.direct(colorSpace)
    guard case .alternative(_, let alternativeNames, _, let route) = alternative.route,
      case .colorSpace(.deviceRGB) = route
    else {
      Issue.record("Expected a frozen alternative-color route")
      return
    }
    #expect(alternativeNames == ["Spot"])
  }

  @Test func storedSelectionPreservesSourceAndEffectiveObjects() throws {
    let whitePoint = try Object.array(
      [.integer(1), .integer(1), .integer(1)],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    let dictionary = try Object.dictionary(
      uniqueKeysWithValues: [(.literalName("WhitePoint"), whitePoint)],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    let source = try Object.array(
      [.literalName("CIEBasedA"), dictionary],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    let parameters = PostScriptColorSpace.CIE(
      whitePoint: .init(x: 1, y: 1, z: 1),
      blackPoint: .init(x: 0, y: 0, z: 0),
      range: [try .init(0, 1)],
      decode: [],
      initialTransform: .matrix([1, 1, 1]),
      rangeABC: [try .init(0, 1), try .init(0, 1), try .init(0, 1)],
      decodeABC: [],
      matrixABC: [1, 0, 0, 0, 1, 0, 0, 0, 1],
      rangeLMN: [try .init(0, 1), try .init(0, 1), try .init(0, 1)],
      decodeLMN: [],
      matrixLMN: [1, 0, 0, 0, 1, 0, 0, 0, 1]
    )
    let effective = PostScriptColorSpace.cieA(source: source, parameters: parameters)
    let selection = PostScriptColorSelection(
      source: .deviceGray(nil),
      route: .colorSpace(effective)
    )

    let restored = PostScriptColorSelection.Stored(selection).value
    #expect(restored.source.description == GraphicsColorSpaceDescription.deviceGray)
    guard case .colorSpace(.cieA(let restoredSource, _)) = restored.route else {
      Issue.record("Expected the effective CIE route")
      return
    }
    #expect(restoredSource == source)
  }
}
