import Foundation
import SolidColor
import Testing

@testable import SolidPostScript

@Suite struct ShadingTests {
  @Test func axialShfillRecordsSemanticGeometryAndLeavesPathAndColorUntouched() async throws {
    let result = try await Interpreter.render(
      content: """
      0.25 setgray 1 2 moveto
      << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 20 0]
         /Function << /FunctionType 2 /Domain [0 1]
                      /C0 [1 0 0] /C1 [0 0 1] /N 1 >>
         /Extend [true true]
      >> shfill
      currentgray currentpoint showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(try values[0].value(as: RealValue.self).value == 2)
    #expect(try values[1].value(as: RealValue.self).value == 1)
    #expect(try values[2].value(as: RealValue.self).value == 0.25)
    let page = try #require(result.output.pages.first)
    guard case .shading(let shading, _) = try #require(page.effects.first) else {
      Issue.record("Expected a shading effect")
      return
    }
    #expect(shading.type == 2)
    #expect(!shading.mesh.triangles.isEmpty)
    guard case .axial = shading.geometry else {
      Issue.record("Expected retained axial geometry")
      return
    }
  }

  @Test func typeOneAndRadialShadingsCompilePortableMeshes() async throws {
    let typeOne = try await Interpreter.render(
      content: """
      << /ShadingType 1 /ColorSpace /DeviceGray /Domain [0 1 0 1]
         /Matrix [20 0 0 20 0 0]
         /Function << /FunctionType 0 /Domain [0 1 0 1] /Range [0 1]
                      /Size [2 2] /BitsPerSample 8 /DataSource <00ffff00> >>
      >> shfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let radial = try await Interpreter.render(
      content: """
      << /ShadingType 3 /ColorSpace /DeviceGray /Coords [10 10 0 10 10 10]
         /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>
      >> shfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    #expect(try #require(typeOne.output.pages.first).effects.count == 1)
    #expect(try #require(radial.output.pages.first).effects.count == 1)
  }

  @Test func axialDomainMayRunInDescendingParameterOrder() async throws {
    let result = try await Interpreter.render(
      content: """
      << /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 10 0] /Domain [1 0]
         /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>
      >> shfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    #expect(try #require(result.output.pages.first).effects.count == 1)
  }

  @Test func sampledAndStitchingFunctionsAcceptDegenerateDomains() throws {
    let sampled = try ColorSampledFunction(
      domain: [ColorComponentRange(0.5, 0.5)],
      range: [ColorComponentRange(0.25, 0.25)],
      size: [2],
      bitsPerSample: 8,
      order: 3,
      encode: [1, 0],
      sampleData: Data([0, 255])
    )
    #expect(try sampled.evaluate([1]) == [0.25])

    let exponential = try ColorExponentialFunction(
      domain: ColorComponentRange(0.5, 0.5),
      c0: [0],
      c1: [1],
      exponent: 2
    )
    let stitching = try ColorStitchingFunction(
      domain: ColorComponentRange(2, 2),
      functions: [.exponential(exponential)],
      bounds: [],
      encode: [0.25, 0.75]
    )
    #expect(try stitching.evaluate([10]) == [0.25])
  }

  @Test func arrayTriangleAndPatchMeshesSupportAllFourMeshTypes() async throws {
    let programs = [
      "<< /ShadingType 4 /ColorSpace /DeviceGray /DataSource [0 0 0 0 0 20 0 1 0 0 20 0] >>",
      "<< /ShadingType 5 /ColorSpace /DeviceGray /VerticesPerRow 2 /DataSource [0 0 0 20 0 1 0 20 0 20 20 1] >>",
      "<< /ShadingType 6 /ColorSpace /DeviceGray /DataSource [0 0 0 0 7 0 13 0 20 7 20 13 20 20 20 20 13 20 7 20 0 13 0 7 0 0 1 1 0] >>",
      "<< /ShadingType 7 /ColorSpace /DeviceGray /DataSource [0 0 0 0 7 0 13 0 20 7 20 13 20 20 20 20 13 20 7 20 0 13 0 7 0 7 7 7 13 13 13 13 7 0 1 1 0] >>",
    ]
    for program in programs {
      let result = try await Interpreter.render(
        content: "\(program) shfill showpage",
        to: RecordingGraphicsTarget()
      )
      let page = try #require(result.output.pages.first)
      guard case .shading(let shading, _) = try #require(page.effects.first) else {
        Issue.record("Expected mesh shading")
        continue
      }
      #expect(!shading.mesh.triangles.isEmpty)
    }
  }

  @Test func malformedMeshDataUsesRangecheckThroughErrordict() async throws {
    let error: NameValue = try await Interpreter.result(content: """
      { << /ShadingType 4 /ColorSpace /DeviceGray /DataSource [1 0 0 0] >> shfill }
      stopped $error /errorname get
      """)
    #expect(error.value == "rangecheck")
  }

  @Test func packedMeshDataUsesHighBitFirstRecordsAndDecodeRanges() async throws {
    let result = try await Interpreter.render(
      content: """
      << /ShadingType 5 /ColorSpace /DeviceGray /VerticesPerRow 2
         /BitsPerCoordinate 8 /BitsPerComponent 8
         /Decode [0 20 0 20 0 1]
         /DataSource <000000ff00ff00ff00ffffff>
      >> shfill showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let page = try #require(result.output.pages.first)
    guard case .shading(let shading, _) = try #require(page.effects.first) else {
      Issue.record("Expected a packed lattice shading")
      return
    }
    #expect(shading.type == 5)
    #expect(shading.mesh.triangles.count == 2)
    #expect(shading.mesh.triangles[0].second.position.x == 20)
  }
}
