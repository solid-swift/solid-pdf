//
//  VM.swift
//
//
//  Created by Kevin Wooten on 7/2/24.
//

import Foundation

/// The PostScript virtual-memory allocation domain.
public enum VM: Sendable {
  case global
  case local
}
