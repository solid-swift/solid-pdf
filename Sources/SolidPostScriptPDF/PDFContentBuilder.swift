import Foundation
import SolidPostScript

struct PDFContentBuilder {
  private(set) var data = Data()

  mutating func command(_ value: String) {
    data.append(contentsOf: value.utf8)
    data.append(0x0A)
  }

  mutating func append(_ value: Data) {
    data.append(value)
  }

  mutating func path(_ path: GraphicsPath, transformedBy matrix: GraphicsMatrix? = nil) {
    for element in path.elements {
      switch element {
      case .move(let point):
        let point = matrix?.transform(point) ?? point
        command("\(number(point.x)) \(number(point.y)) m")
      case .line(let point):
        let point = matrix?.transform(point) ?? point
        command("\(number(point.x)) \(number(point.y)) l")
      case .curve(let first, let second, let end):
        let first = matrix?.transform(first) ?? first
        let second = matrix?.transform(second) ?? second
        let end = matrix?.transform(end) ?? end
        command(
          "\(number(first.x)) \(number(first.y)) \(number(second.x)) \(number(second.y)) "
            + "\(number(end.x)) \(number(end.y)) c"
        )
      case .close:
        command("h")
      }
    }
  }

  mutating func rectangle(_ rect: GraphicsRect) {
    command("\(number(rect.x)) \(number(rect.y)) \(number(rect.width)) \(number(rect.height)) re")
  }

  func number(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    if value == 0 { return "0" }
    var text = String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), value)
    while text.last == "0" { text.removeLast() }
    if text.last == "." { text.removeLast() }
    return text == "-0" ? "0" : text
  }

  func matrix(_ matrix: GraphicsMatrix) -> String {
    "\(number(matrix.a)) \(number(matrix.b)) \(number(matrix.c)) \(number(matrix.d)) "
      + "\(number(matrix.tx)) \(number(matrix.ty))"
  }
}
