import Foundation
@testable import SolidPostScript
import Testing

@Suite
struct StatementScannerTests {

  @Test
  func completeOperatorsDoNotRequireInventedClosingDelimiters() {
    let cases: [(String, StatementScanner.Completion)] = [
      ("1\n", .complete),
      ("[\n", .complete),
      ("]\n", .complete),
      ("<< /key\n", .complete),
      (">>\n", .complete),
      ("/literal\n", .complete),
      ("//immediate\n", .complete),
    ]

    for (source, expected) in cases {
      var scanner = StatementScanner(data: Data(source.utf8), binaryEnabled: false)
      #expect(scanner.completion() == expected)
    }
  }

  @Test
  func compoundLexemesRequireTheirOwnTerminators() {
    let cases: [(String, StatementScanner.Completion)] = [
      ("{ 1\n", .incomplete),
      ("{ 1\n}\n", .complete),
      ("(literal\n", .incomplete),
      ("(literal)\n", .complete),
      ("<4142\n", .incomplete),
      ("<4142>\n", .complete),
      ("<~87cUR\n", .incomplete),
      ("<~87cUR~>\n", .complete),
    ]

    for (source, expected) in cases {
      var scanner = StatementScanner(data: Data(source.utf8), binaryEnabled: false)
      #expect(scanner.completion() == expected)
    }
  }

  @Test
  func lexicalErrorsFormCompleteStatements() {
    let cases = ["}\n", ")\n", ">\n", "<GG\n", "<~!z\n"]

    for source in cases {
      var scanner = StatementScanner(data: Data(source.utf8), binaryEnabled: false)
      #expect(scanner.completion() == .invalid)
    }
  }

  @Test
  func whitespaceAndCommentsDoNotCreateStatements() {
    for source in ["\n", "  % comment\r\n"] {
      var scanner = StatementScanner(data: Data(source.utf8), binaryEnabled: false)
      #expect(scanner.completion() == .empty)
    }
  }

  @Test
  func binaryPayloadLineEndsDoNotTerminateTheStatement() {
    let token = Data([142, 3, Scanner.carriageReturn, Scanner.lineFeed, Scanner.char("A")])

    var partial = StatementScanner(data: Data(token.prefix(4)), binaryEnabled: true)
    #expect(partial.completion() == .incomplete)

    var payloadEndsAtLineFeed = StatementScanner(data: token, binaryEnabled: true)
    #expect(payloadEndsAtLineFeed.completion() == .incomplete)

    var terminated = StatementScanner(data: token + Data([Scanner.lineFeed]), binaryEnabled: true)
    #expect(terminated.completion() == .complete)
  }

  @Test
  func binaryRecognitionTracksTheActiveObjectFormat() {
    let bytes = Data([142, 3, Scanner.carriageReturn])

    var binary = StatementScanner(data: bytes, binaryEnabled: true)
    #expect(binary.completion() == .incomplete)

    var textual = StatementScanner(data: bytes, binaryEnabled: false)
    #expect(textual.completion() == .complete)
  }
}
