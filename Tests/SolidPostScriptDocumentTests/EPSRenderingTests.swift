import Foundation
import SolidIO
import SolidPDF
import SolidPostScript
import SolidPostScriptDocument
import SolidPostScriptPDF
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

  @Test
  func rendersFractionalEPSBoundsAndMetadataToZeroOriginPDF() async throws {
    let document = try PostScriptDocument(data: Data("""
      %!PS-Adobe-3.0 EPSF-3.0
      %%Title: Vector Fixture
      %%Creator: Tests
      %%BoundingBox: -1.5 -2.25 10.25 20.5
      0 setgray -1.5 -2.25 11.75 22.75 rectfill
      """.utf8))
    let result = try await document.renderPDF(options: .init(compressionLevel: 0))
    #expect(result.output.pageCount == 1)
    #expect(result.output.data.containsASCII("/MediaBox [0 0 11.75 22.75]"))
    #expect(result.output.data.containsASCII("Vector Fixture"))
    #expect(result.output.data.containsASCII("Tests"))
  }

  @Test
  func PDFPageSelectionAndDSCLabelsUseTransmittedOrder() async throws {
    let document = try PostScriptDocument(data: Data("""
      %!PS-Adobe-3.0
      %%Pages: 2
      %%Page: first 1
      showpage
      %%Page: second 2
      showpage
      """.utf8))
    let result = try await document.renderPDF(
      options: .init(compressionLevel: 0),
      documentOptions: .init(pages: .pages([2]))
    )
    #expect(result.output.pageCount == 1)
    #expect(result.output.data.containsASCII("/PageLabels"))
    #expect(result.output.data.containsASCII("second"))
  }
}

private extension Data {
  func containsASCII(_ value: String) -> Bool {
    range(of: Data(value.utf8)) != nil
  }
}
