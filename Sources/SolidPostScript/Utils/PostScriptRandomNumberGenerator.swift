//
//  PostScriptRandomNumberGenerator.swift
//  SolidPDF
//
//  Created by Kevin Wooten on 8/15/26.
//

/// The deterministic pseudo-random number generator used by PostScript's random operators.
struct PostScriptRandomNumberGenerator {

  private var state: UInt32

  var restorableState: Int32 { Int32(bitPattern: state) }

  init(seed: Int32) {
    self.state = UInt32(bitPattern: seed)
  }

  mutating func next() -> Int32 {
    state = state &* 0x4C95_7F2D &+ 1
    return Int32(state & 0x7FFF_FFFF)
  }
}
