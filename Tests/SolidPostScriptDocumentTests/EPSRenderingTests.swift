import Foundation
import SolidIO
import SolidPostScript
import SolidPostScriptDocument
import Testing

@Suite
struct EPSRenderingTests {
  @Test
  func rendersOneBoundingBoxSizedPageAndSuppressesShowPage() async throws {
    let document = try PostScriptDocument(data: Data("""
      %!PS-Adobe-3.0 EPSF-3.0
      %%BoundingBox: -1.5 -2.25 10.25 20.5
      0 setgray -1.5 -2.25 11.75 22.75 rectfill
      showpage
      """.utf8))
    let result = try await document.renderRaster(options: .init(dpi: 144))
    #expect(result.output.count == 1)
    #expect(result.output[0].width == 24)
    #expect(result.output[0].height == 46)
  }

  @Test
  func strictEPSRejectsOperandLeak() async throws {
    let document = try PostScriptDocument(data: Data("""
      %!PS-Adobe-3.0 EPSF-3.0
      %%BoundingBox: 0 0 10 10
      1
      """.utf8))
    await #expect(throws: (any Swift.Error).self) {
      try await document.renderRaster()
    }
  }

  @Test
  func stagedInputExecutesTheLogicalStandardInputFile() async throws {
    let data = Data("""
      %!PS-Adobe-3.0 EPSF-3.0
      %%BoundingBox: 0 0 10 10
      currentfile (%stdin) (r) file eq not { 1 (not stdin) add } if
      """.utf8)
    let document = try PostScriptDocument.stagedStandardInput(data)
    let host = InterpreterHostConfiguration(
      standardInput: DataSource(data: document.programData),
      interactiveExecutiveEnabled: false
    )
    let environment = InterpreterEnvironment(hostConfiguration: host, fileDevices: FileDevices(devices: []))
    let result = try await document.renderRaster(environment: environment)
    #expect(result.output.count == 1)
  }
}
