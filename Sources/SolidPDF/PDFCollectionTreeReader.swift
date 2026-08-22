import Foundation

enum PDFCollectionTreeKey: Sendable, Hashable, Comparable {
  case name(Data)
  case number(Int64)

  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.name(let lhs), .name(let rhs)):
      return lhs.lexicographicallyPrecedes(rhs)
    case (.number(let lhs), .number(let rhs)):
      return lhs < rhs
    case (.name, .number):
      return true
    case (.number, .name):
      return false
    }
  }
}

struct PDFCollectionTreeEntry: Sendable, Hashable {
  let key: PDFCollectionTreeKey
  let value: PDFObject
}

struct PDFCollectionTreeReader {
  enum Kind {
    case name
    case number

    var valuesKey: PDFName {
      switch self {
      case .name: "Names"
      case .number: "Nums"
      }
    }
  }

  typealias Resolver = @Sendable (PDFObjectReference) async throws -> PDFIndirectObject

  let kind: Kind
  let limits: PDFParsingLimits
  let resolve: Resolver

  func read(_ root: PDFObject) async throws -> [PDFCollectionTreeEntry] {
    let result = try await readNode(root, depth: 0, visited: [])
    guard result.entries.count <= limits.maximumArrayElements else {
      throw limit("A collection tree contains too many entries.")
    }
    return result.entries
  }

  private struct Result {
    let entries: [PDFCollectionTreeEntry]
    let visited: Set<PDFObjectReference>
    let lower: PDFCollectionTreeKey?
    let upper: PDFCollectionTreeKey?
    let storage: Int
  }

  private func readNode(
    _ object: PDFObject,
    depth: Int,
    visited: Set<PDFObjectReference>
  ) async throws -> Result {
    guard depth <= limits.maximumNesting else {
      throw limit("A collection tree exceeds its nesting limit.")
    }
    let dictionary: [PDFName: PDFObject]
    var nextVisited = visited
    switch object {
    case .dictionary(let value):
      dictionary = value
    case .reference(let reference):
      guard nextVisited.insert(reference).inserted else {
        throw PDFParsingError.referenceCycle(Array(nextVisited) + [reference])
      }
      let resolved = try await resolve(reference)
      guard case .value(.dictionary(let value)) = resolved.value else {
        throw malformed("A collection-tree child must be an ordinary dictionary.")
      }
      dictionary = value
    default:
      throw malformed("A collection-tree root must be a dictionary or reference.")
    }

    let kids = dictionary.pdfArray(named: "Kids")
    let values = dictionary.pdfArray(named: kind.valuesKey)
    guard (kids == nil) != (values == nil) else {
      throw malformed("A collection-tree node must contain exactly one of Kids or values.")
    }

    var entries = [PDFCollectionTreeEntry]()
    var storage = dictionary.count * 32
    if let kids {
      guard !kids.isEmpty else { throw malformed("A collection-tree Kids array is empty.") }
      var lastUpper: PDFCollectionTreeKey?
      for kid in kids {
        guard case .reference = kid else {
          throw malformed("Collection-tree children must be indirect references.")
        }
        let result = try await readNode(kid, depth: depth + 1, visited: nextVisited)
        nextVisited.formUnion(result.visited)
        if let lastUpper, let lower = result.lower, lower <= lastUpper {
          throw malformed("Collection-tree child ranges overlap or are unsorted.")
        }
        lastUpper = result.upper
        entries.append(contentsOf: result.entries)
        storage = try checkedAdd(storage, result.storage)
      }
    } else if let values {
      guard values.count.isMultiple(of: 2) else {
        throw malformed("A collection-tree values array must contain key/value pairs.")
      }
      var previous: PDFCollectionTreeKey?
      for index in stride(from: 0, to: values.count, by: 2) {
        let key = try parseKey(values[index])
        if let previous, key <= previous {
          throw malformed("Collection-tree keys must be sorted and unique.")
        }
        previous = key
        entries.append(PDFCollectionTreeEntry(key: key, value: values[index + 1]))
        storage = try checkedAdd(storage, keyStorage(key) + 32)
      }
    }

    let lower = entries.first?.key
    let upper = entries.last?.key
    if let limitsValue = dictionary.pdfArray(named: "Limits") {
      guard limitsValue.count == 2,
        let lower,
        let upper,
        try parseKey(limitsValue[0]) == lower,
        try parseKey(limitsValue[1]) == upper
      else {
        throw malformed("Collection-tree Limits do not match the node's entries.")
      }
    } else if depth > 0 {
      throw malformed("A nonroot collection-tree node requires exact Limits.")
    }
    guard storage <= limits.maximumPageTreeScratchBytes else {
      throw limit("Collection-tree validation exceeds its storage limit.")
    }
    return Result(
      entries: entries,
      visited: nextVisited,
      lower: lower,
      upper: upper,
      storage: storage
    )
  }

  private func parseKey(_ object: PDFObject) throws -> PDFCollectionTreeKey {
    switch (kind, object) {
    case (.name, .string(let string)):
      return .name(string.bytes)
    case (.number, .number(.integer(let integer))):
      return .number(integer)
    default:
      throw malformed("A collection-tree key has the wrong type.")
    }
  }

  private func keyStorage(_ key: PDFCollectionTreeKey) -> Int {
    switch key {
    case .name(let data): data.count
    case .number: MemoryLayout<Int64>.size
    }
  }

  private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, result <= limits.maximumPageTreeScratchBytes else {
      throw limit("Collection-tree validation exceeds its storage limit.")
    }
    return result
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  private func limit(_ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: 0, message: message))
  }
}
