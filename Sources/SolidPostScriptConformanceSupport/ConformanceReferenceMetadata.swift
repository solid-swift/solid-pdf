import Foundation

package struct ConformanceReferenceMetadata: Codable, Sendable, Hashable {
  package let executable: String
  package let version: String
  package let archiveSHA256: String
  package let baseArguments: [String]

  package init(executable: String, version: String) {
    self.executable = executable
    self.version = version
    archiveSHA256 = "1cdb766de8db8f1e589c817f09c5855ea5f65dfc8540e465a69ac14c18416025"
    baseArguments = ["-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-dNOFONTMAP"]
  }

  package func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self) + Data([0x0A])
  }
}
