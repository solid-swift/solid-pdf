//
//  RestorableValue.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation

/// A PostScript restorable value.
public protocol RestorableValue {

  func save(to snapshot: Snapshot.Builder)

}

protocol SnapshotIdentifiableValue {

  var snapshotIdentity: ObjectIdentifier { get }

}
