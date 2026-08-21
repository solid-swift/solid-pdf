import Foundation
import Testing

@testable import SolidPostScript

@Suite struct EExecTests {
  @Test func decryptsAndExecutesBinaryAndHexadecimalStrings() async throws {
    let binary = Self.encryptedStringProgram("1 2 add currentfile closefile ", transport: .binary)
    let hexadecimal = Self.encryptedStringProgram("4 5 add currentfile closefile ", transport: .hexadecimal)
    let results = try await Interpreter.results(content: "\(binary) eexec \(hexadecimal) eexec")
    #expect(try results[1].value(as: IntegerValue.self).value == 3)
    #expect(try results[0].value(as: IntegerValue.self).value == 9)
  }

  @Test func implicitEndOfDataClosesTheScope() async throws {
    let encrypted = Self.encryptedStringProgram("8 9 add ", transport: .binary)
    let results = try await Interpreter.results(content: "countdictstack /before exch def \(encrypted) eexec before countdictstack")
    #expect(try results[2].value(as: IntegerValue.self).value == 17)
    let before = try results[1].value(as: IntegerValue.self).value
    let after = try results[0].value(as: IntegerValue.self).value
    #expect(before == after)
  }

  @Test func hexadecimalTransportAcceptsWhitespaceAfterItsInitialEightCharacters() async throws {
    let ciphertext = Self.encrypt(Data("6 7 add currentfile closefile ".utf8))
    let encoded = Self.hexadecimal(ciphertext)
    let split = encoded.index(encoded.startIndex, offsetBy: 8)
    let spaced = encoded[..<split] + encoded[split...].chunks(ofCount: 2).joined(separator: " \n\t")
    let result: IntegerValue = try await Interpreter.result(content: "(\(spaced)) eexec")
    #expect(result.value == 13)
  }

  @Test func currentFileReadsDecryptedBytesAndClosesImmediately() async throws {
    let plaintext = "currentfile 1 string readstring Zpop 0 get { currentfile closefile countdictstack } exec "
    let encrypted = Self.encryptedStringProgram(plaintext, transport: .binary)
    let results = try await Interpreter.results(content: "countdictstack /before exch def \(encrypted) eexec before countdictstack")
    let explicitByte = try results[3].value(as: IntegerValue.self).value
    #expect(explicitByte == 90)
    let before = try results[1].value(as: IntegerValue.self).value
    let after = try results[0].value(as: IntegerValue.self).value
    #expect(before == after)
  }

  @Test func outerCurrentFileResumesAtTheExactBinaryAndHexadecimalTrailer() async throws {
    for transport in [Transport.binary, .hexadecimal] {
      var program = Data("/source currentfile def 10 source eexec\n".utf8)
      program.append(Self.transport(Self.encrypt(Data("5 currentfile closefile ".utf8)), as: transport))
      program.append(Data(" add source status 99".utf8))
      let context = try await Interpreter.execute(file: DataFile(data: program, mode: .read))
      let results = try await context.results()
      #expect(try results[1].value(as: BooleanValue.self).value)
      #expect(try results[2].value(as: IntegerValue.self).value == 15)
    }
  }

  @Test func systemDictionaryHasPrecedenceAndOriginalDictionaryStackIsRestored() async throws {
    let plaintext = "userdict /inside countdictstack put 1 2 add { currentfile closefile userdict /after countdictstack put } exec "
    let encrypted = Self.encryptedStringProgram(plaintext, transport: .binary)
    let results = try await Interpreter.results(content: """
      /add { pop pop 99 } def
      countdictstack /before exch def
      \(encrypted) eexec
      userdict /inside get userdict /after get before countdictstack
      """)
    #expect(try results[4].value(as: IntegerValue.self).value == 3)
    let inside = try results[3].value(as: IntegerValue.self).value
    let after = try results[2].value(as: IntegerValue.self).value
    let before = try results[1].value(as: IntegerValue.self).value
    let final = try results[0].value(as: IntegerValue.self).value
    #expect(inside == before + 1)
    #expect(after == before)
    #expect(final == before)
  }

  @Test func nestedScopesRestoreTheirDictionaryStacksInLIFOOrder() async throws {
    let inner = Self.encryptedStringProgram("1 currentfile closefile ", transport: .binary)
    let outerPlaintext = "\(inner) eexec 2 currentfile closefile "
    let outer = Self.encryptedStringProgram(outerPlaintext, transport: .binary)
    let results = try await Interpreter.results(content: "\(outer) eexec")
    #expect(try results[1].value(as: IntegerValue.self).value == 1)
    #expect(try results[0].value(as: IntegerValue.self).value == 2)
  }

  @Test func inputStringIsNotModifiedAndFilteredSourcesAreAccepted() async throws {
    let ciphertext = Self.encrypt(Data("42 currentfile closefile ".utf8))
    let binaryString = "<\(Self.hexadecimal(ciphertext))>"
    let filterSource = "(\(Self.hexadecimal(ciphertext))>) /ASCIIHexDecode filter"
    let results = try await Interpreter.results(content: """
      /encrypted \(binaryString) def /copy encrypted dup length string copy def
      encrypted eexec encrypted copy eq
      \(filterSource) eexec
      """)
    #expect(try results[2].value(as: IntegerValue.self).value == 42)
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[0].value(as: IntegerValue.self).value == 42)
  }

  @Test func malformedTransportRaisesIOErrorWithEExecAsCommand() async throws {
    for operand in ["(123)", "(0000ZZZZ)", "(00000000A)"] {
      let results = try await Interpreter.results(content: """
        { \(operand) eexec } stopped
        $error /errorname get /ioerror eq
        $error /command get /eexec load eq
        """)
      let checks = results.compactMap { ($0.value as? BooleanValue)?.value }
      #expect(checks == [true, true, true])
    }
  }

  @Test func validationErrorsPreserveOperandsAndCommands() async throws {
    let results = try await Interpreter.results(content: """
      { 17 eexec } stopped
      $error /errorname get /typecheck eq $error /command get /eexec load eq
      { (%stdout) (w) file eexec } stopped
      $error /errorname get /invalidfileaccess eq $error /command get /eexec load eq
      { (00000000) noaccess eexec } stopped
      $error /errorname get /invalidaccess eq $error /command get /eexec load eq
      """)
    let checks = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(checks == [true, true, true, true, true, true, true, true, true])
    #expect(results.contains { ($0.value as? IntegerValue)?.value == 17 })
  }

  @Test func stackAndDictionaryLimitsUseEExecAsTheFailingCommand() async throws {
    let stackResults = try await Interpreter.results(content: """
      { eexec } stopped
      $error /errorname get /stackunderflow eq
      $error /command get /eexec load eq
      """)
    #expect(stackResults.compactMap { ($0.value as? BooleanValue)?.value } == [true, true, true])

    let dictionaryResults = try await Interpreter.results(content: """
      << /MaxDictStack 3 >> setuserparams
      { (00000000) eexec } stopped clear
      $error /errorname get /dictstackoverflow eq
      $error /command get /eexec load eq
      """)
    #expect(dictionaryResults.compactMap { ($0.value as? BooleanValue)?.value } == [true, true])
  }

  @Test func decryptedErrorsUnwindTheScopeAndRetainTheirActualCommand() async throws {
    let encrypted = Self.encryptedStringProgram("missingEExecName ", transport: .binary)
    let results = try await Interpreter.results(content: """
      countdictstack /before exch def
      { \(encrypted) eexec } stopped
      $error /errorname get /undefined eq
      $error /command get /missingEExecName eq
      before countdictstack eq
      """)
    let checks = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(checks == [true, true, true, true])
  }

  @Test func encryptedPFAFontCanBeDefinedMeasuredAndRendered() async throws {
    let cleartext = """
      %!PS-AdobeFont-1.0: EExecFixture 1.0
      mark 16 dict dup begin
        /FontType 1 def /FontMatrix [0.001 0 0 0.001 0 0] def
        /FontBBox [0 0 600 700] def /Encoding StandardEncoding def
      currentdict end
      currentfile eexec
      """
    let encrypted = """
      dup /Private 2 dict dup begin /lenIV -1 def end put
      dup /CharStrings 2 dict dup begin
        /.notdef <8BF8EC0D0E> def
        /A <8BF8EC0D8B8B15F8888B8BF950FC888B8BFDB005090E> def
      end put
      dup /FontName /EExecFixture put
      pop
      /EExecFixture exch definefont pop
      currentfile closefile
      """
    let trailer = """
      cleartomark
      /EExecFixture findfont 100 scalefont setfont
      (A) stringwidth
      20 20 moveto (A) show showpage
      """
    var program = Data(cleartext.utf8)
    program.append(10)
    program.append(Self.transport(Self.encrypt(Data(encrypted.utf8)), as: .hexadecimal))
    program.append(Data(trailer.utf8))

    let result = try await Interpreter.render(
      file: DataFile(data: program, mode: .read),
      to: RecordingGraphicsTarget()
    )
    let values = try await result.context.results()
    #expect(abs(try values[1].value(as: RealValue.self).value - 60) < 1e-9)
    #expect(abs(try values[0].value(as: RealValue.self).value) < 1e-9)
    let page = try #require(result.output.pages.first)
    #expect(page.effects.contains { effect in
      if case .text = effect { return true }
      return false
    })
  }

  private enum Transport {
    case binary
    case hexadecimal
  }

  private static func encryptedStringProgram(_ plaintext: String, transport: Transport) -> String {
    let bytes = Self.transport(encrypt(Data(plaintext.utf8)), as: transport)
    return "<\(hexadecimal(bytes))>"
  }

  private static func encrypt(_ plaintext: Data) -> Data {
    var state: UInt16 = 55_665
    var result = Data(capacity: plaintext.count + 4)
    for byte in Data([0, 0, 0, 0]) + plaintext {
      let ciphertext = byte ^ UInt8(truncatingIfNeeded: state >> 8)
      state = UInt16(truncatingIfNeeded: (UInt32(ciphertext) + UInt32(state)) * 52_845 + 22_719)
      result.append(ciphertext)
    }
    return result
  }

  private static func transport(_ ciphertext: Data, as transport: Transport) -> Data {
    switch transport {
    case .binary:
      ciphertext
    case .hexadecimal:
      Data(hexadecimal(ciphertext).utf8)
    }
  }

  private static func hexadecimal(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
  }
}
