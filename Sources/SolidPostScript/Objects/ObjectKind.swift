//
//  ObjectKind.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An PostScript object kind.
public enum ObjectKind: Equatable, Hashable, Sendable {
  case executable
  case literal
}
