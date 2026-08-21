import Foundation
import Testing

@testable import SolidPostScript

@Suite struct FontDataTests {
  @Test func fontSetStartDataDefinesTheSetAndConstituentFonts() async throws {
    let cff = minimalCompactFont()
    var program = Data("/FontSetInit /ProcSet findresource begin /Set \(cff.count) StartData ".utf8)
    program.append(cff)
    program.append(Data(" end /Set /FontSet findresource /Test known /Test /Font findresource /FontType get".utf8))

    let context = try await Interpreter.execute(file: DataFile(data: program, mode: .read))
    let results = try await context.results()
    #expect(try results[0].value(as: IntegerValue.self).value == 2)
    #expect(try results[1].value(as: BooleanValue.self).value)
  }

  @Test func cidStartDataConsumesExactBinaryBytesAndLeavesTrailingProgram() async throws {
    let prefix = """
      /CIDInit /ProcSet findresource begin
      20 dict begin
        /CIDFontType 0 def /FontType 9 def /CIDFontName /BinaryCID def
        /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def
        /CIDCount 1 def /FontMatrix [.001 0 0 .001 0 0] def /FontBBox [0 0 1 1] def
        (Binary) 3 StartData
      """ + " "
    var program = Data(prefix.utf8)
    program.append(contentsOf: [65, 66, 67])
    program.append(Data(" end end /BinaryCID /CIDFont findresource /GlyphData get length 123".utf8))

    let context = try await Interpreter.execute(file: DataFile(data: program, mode: .read))
    let results = try await context.results()
    #expect(try results[0].value(as: IntegerValue.self).value == 123)
    #expect(try results[1].value(as: IntegerValue.self).value == 3)
  }

  @Test func standardFMapTypeResourcesAreExactlyTypesTwoThroughNine() throws {
    let provider = IntegerImplicitResources(category: "FMapType", values: Operators.standardFMapTypes)
    let values = try provider.enumerateResources(matching: "*").map {
      try $0.value(as: IntegerValue.self).value
    }

    #expect(values == Array(2...9))
  }

  private func minimalCompactFont() -> Data {
    var data = Data([1, 0, 4, 4])
    data.append(contentsOf: [0, 1, 1, 1, 5])
    data.append(contentsOf: "Test".utf8)
    data.append(contentsOf: [0, 1, 1, 1, 7, 29, 0, 0, 0, 28, 17])
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(contentsOf: [0, 1, 1, 1, 2, 14])
    return data
  }
}
