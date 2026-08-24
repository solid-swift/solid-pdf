import Foundation

package enum ConformanceDiscoveryDiagnostic {
  package static func normalize(_ data: Data, prefix: String) -> String {
    normalize(String(decoding: data, as: UTF8.self), prefix: prefix)
  }

  package static func normalize(_ value: String, prefix: String) -> String {
    let lines = value.split(whereSeparator: \.isNewline).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    let selected = lines.last(where: { $0.hasPrefix("Error:") }) ?? lines.last ?? "unknown failure"
    let words = selected.split(whereSeparator: \.isWhitespace).map { word in
      let value = String(word)
      return value.hasPrefix("/") ? "<path>" : value
    }
    return "\(prefix): \(words.joined(separator: " "))"
  }
}
