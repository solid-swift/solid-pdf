//
//  IdiomRecognizer.swift
//

import Foundation

enum IdiomRecognizer {

  private static let maximumComparisonDepth = 10

  static func recognize(candidate: Object, context: isolated Context) throws -> Object {
    guard context.userParameters.boolean("IdiomRecognition") else { return candidate }

    let candidateVM = try candidate.value(as: (any CompositeValue).self).vm
    for (_, entry) in try ResourceRuntime.storedEntries(in: "IdiomSet", context: context) {
      let dictionary = try entry.instance.value(as: DictionaryValue.self)
      var replacement: Object?
      try dictionary.forEachUnchecked { _, pairObject in
        guard replacement == nil, let pair = pairObject.value as? ArrayValue else { return }
        let procedures = uncheckedElements(of: pair)
        guard procedures.count == 2, proceduresMatch(candidate, procedures[0], depth: 0) else { return }

        let substitute = procedures[1]
        if candidateVM == .global,
          let composite = substitute.value as? any CompositeValue,
          composite.vm == .local
        {
          return
        }
        replacement = substitute
      }
      if let replacement { return replacement }
    }
    return candidate
  }

  private static func proceduresMatch(_ lhs: Object, _ rhs: Object, depth: Int) -> Bool {
    if lhs == rhs { return true }
    guard depth < maximumComparisonDepth,
      let lhsArray = lhs.value as? any CollectionValue,
      let rhsArray = rhs.value as? any CollectionValue,
      lhsArray.count == rhsArray.count
    else {
      return false
    }

    return zip(uncheckedElements(of: lhsArray), uncheckedElements(of: rhsArray))
      .allSatisfy { proceduresMatch($0.0, $0.1, depth: depth + 1) }
  }

  private static func uncheckedElements(of collection: any CollectionValue) -> [Object] {
    var elements: [Object] = []
    elements.reserveCapacity(Int(collection.count))
    collection.forEachUnchecked { elements.append($0) }
    return elements
  }
}
