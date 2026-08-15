//
//  ProcSet.swift
//
//
//  Created by Kevin Wooten on 7/10/24.
//

import Foundation

/// A PostScript proc set.
public protocol ProcSet: Sendable {

  var name: String { get }

  func load() -> String

}
