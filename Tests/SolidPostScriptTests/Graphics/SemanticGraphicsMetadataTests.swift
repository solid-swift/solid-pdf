import Foundation
import Testing

@testable import SolidPostScript

@Suite struct SemanticGraphicsMetadataTests {
  @Test func pageCoordinateMappingUsesTheInstalledDefaultMatrix() throws {
    let descriptor = GraphicsDeviceDescriptor(
      mediaBounds: GraphicsRect(x: 0, y: 0, width: 200, height: 400),
      imageableBounds: GraphicsRect(x: 10, y: 20, width: 180, height: 360),
      horizontalResolution: 144,
      verticalResolution: 144,
      defaultMatrix: GraphicsMatrix(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0)
    )

    let mapping = GraphicsPageCoordinateMapping(device: descriptor)

    #expect(mapping.pageToDevice.transform(.init(x: 5, y: 7)) == .init(x: 10, y: 14))
    #expect(mapping.deviceToPage?.transform(.init(x: 10, y: 14)) == .init(x: 5, y: 7))
    #expect(mapping.mediaBounds == GraphicsRect(x: 0, y: 0, width: 100, height: 200))
    #expect(mapping.imageableBounds == GraphicsRect(x: 5, y: 10, width: 90, height: 180))
  }

  @Test func singularPageCoordinateMappingRemainsUnavailable() {
    let descriptor = GraphicsDeviceDescriptor(
      mediaBounds: GraphicsRect(x: 0, y: 0, width: 100, height: 100),
      imageableBounds: GraphicsRect(x: 0, y: 0, width: 100, height: 100),
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: GraphicsMatrix(a: 0, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    )

    let mapping = GraphicsPageCoordinateMapping(device: descriptor)

    #expect(mapping.deviceToPage == nil)
    #expect(mapping.mediaBounds == nil)
    #expect(mapping.imageableBounds == nil)
  }

  @Test func cachedFormsReuseSemanticResourceIdentity() async throws {
    let result = try await Interpreter.render(
      content: """
      /f <<
        /FormType 1
        /BBox [0 0 10 10]
        /Matrix [1 0 0 1 0 0]
        /PaintProc { pop 0 0 10 10 rectfill }
      >> def
      f execform f execform showpage
      """,
      to: RecordingGraphicsTarget()
    )
    let effects = try #require(result.output.pages.first?.effects)
    guard case .form(let first, _) = effects[0], case .form(let second, _) = effects[1] else {
      Issue.record("Expected two form effects")
      return
    }

    #expect(!first.resourceIdentifier.isAnonymous)
    #expect(first.resourceIdentifier == second.resourceIdentifier)
    #expect(!first.displayList.resourceIdentifier.isAnonymous)
  }

  @Test func sampledImagesRetainSourceDescriptionAndRawSamples() async throws {
    let result = try await Interpreter.render(
      content: """
      << /ImageType 1 /Width 1 /Height 1 /BitsPerComponent 4
         /ImageMatrix [1 0 0 1 0 0] /Decode [0 1] /DataSource <A0> >> image
      showpage
      """,
      to: RecordingGraphicsTarget()
    )
    guard case .image(let image, _)? = result.output.pages.first?.effects.first else {
      Issue.record("Expected one recorded image")
      return
    }

    #expect(image.descriptor.sourceType == .sampled)
    #expect(image.descriptor.sourceBitsPerComponent == 4)
    #expect(image.descriptor.sourceComponentCount == 1)
    #expect(image.descriptor.decode == [0, 1])
    #expect(!image.descriptor.resourceIdentifier.isAnonymous)
    #expect(image.rawSamples == Data([0, 10]))
  }

  @Test func recordedCopiesRetainOneLogicalTransmissionAndDistinctOrdinals() async throws {
    let result = try await Interpreter.render(
      content: "<< /NumCopies null >> setpagedevice /#copies 2 def 0 0 1 1 rectfill showpage",
      to: RecordingGraphicsTarget()
    )

    #expect(result.output.pages.map(\.copyOrdinal) == [1, 2])
    #expect(result.output.pages.allSatisfy { $0.transmission.copies == 2 })
    #expect(result.output.pages.map(\.transmission.logicalOrdinal) == [1, 1])
    #expect(result.output.pages.allSatisfy { $0.device == result.output.pages[0].device })
  }
}
