//
//  LoopExitTransfer.swift
//  SolidPostScript
//

import Foundation

/// Targets a single dynamically enclosing PostScript looping context.
struct LoopExitTransfer: Swift.Error {
  let boundaryIdentifier: UInt64
}
