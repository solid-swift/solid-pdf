import Foundation
import SolidFuzzSupport
import SolidPostScript

let configuration = try DeterministicFuzzConfiguration.commandLine()
let runner = DeterministicFuzzRunner(
  configuration: configuration,
  builtInCorpus: [
    Array("(87cURD]j7BEbo80) /ASCII85Decode filter 64 string readstring pop pop".utf8),
    Array("<789c030000000001> /FlateDecode filter 64 string readstring pop pop".utf8),
    Array("<80> /RunLengthDecode filter 64 string readstring pop pop".utf8),
    Array("<< /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns 4 >>".utf8),
  ]
)
try await runner.runAsync { input, iteration in
  let encoded = input.prefix(4_096).map { byte -> UInt8 in
    switch byte {
    case 0, 10, 13, 37, 40, 41, 60, 62, 91, 93, 123, 125:
      return 32
    default:
      return byte < 32 || byte > 126 ? UInt8(48 + Int(byte % 10)) : byte
    }
  }
  let names = ["ASCIIHexDecode", "ASCII85Decode", "RunLengthDecode", "FlateDecode", "LZWDecode"]
  let name = names[iteration % names.count]
  let predictor = Int(input.first ?? 1) % 16
  let program = """
  /payload <\(encoded.map { String(format: "%02x", $0) }.joined())> def
  { payload << /Predictor \(predictor) /Colors 1 /BitsPerComponent 8 /Columns 8 >> /\(name) filter
    dup bytesavailable pop 256 string readstring pop pop closefile
  } stopped pop
  """
  _ = try await Interpreter.execute(content: program)
}
