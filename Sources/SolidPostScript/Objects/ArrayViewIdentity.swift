//
//  ArrayViewIdentity.swift
//

import Foundation

/// Identifies the PostScript value represented by a view into shared array storage.
struct ArrayViewIdentity: Hashable, Sendable {

  let storage: ObjectIdentifier
  let range: Range<Int>
}

/// An array-like value whose language-visible view may select part of shared backing storage.
protocol SharedBackingArrayValue: CollectionValue, SnapshotIdentifiableValue {

  var refRange: StorageRange { get }

  func forEachBackingUnchecked(_ block: (Object) throws -> Void) rethrows
}

extension SharedBackingArrayValue {

  var arrayViewIdentity: ArrayViewIdentity {
    ArrayViewIdentity(storage: snapshotIdentity, range: refRange)
  }
}
