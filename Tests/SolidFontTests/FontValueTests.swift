import Foundation
import SolidFont
import Testing

@Suite struct FontValueTests {
  @Test func bitmapRequiresCompleteRows() throws {
    let bitmap = try FontGlyphBitmap(
      width: 2,
      height: 2,
      bytesPerRow: 2,
      originX: 0,
      originY: 0,
      coverage: Data([0, 1, 2, 3])
    )
    #expect(bitmap.coverage.count == 4)

    #expect(throws: FontError.invalidData) {
      _ = try FontGlyphBitmap(
        width: 2,
        height: 2,
        bytesPerRow: 2,
        originX: 0,
        originY: 0,
        coverage: Data([0, 1, 2])
      )
    }
  }

  @Test func nonType3AssetRequiresData() throws {
    let descriptor = try FontDescriptor(postScriptName: "FixtureFont")
    #expect(throws: FontError.invalidData) {
      _ = try FontAsset(descriptor: descriptor, format: .sfnt)
    }
    let type3 = try FontAsset(descriptor: descriptor, format: .type3)
    #expect(type3.data == nil)
  }
}
