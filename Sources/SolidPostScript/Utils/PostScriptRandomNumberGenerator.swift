//
//  PostScriptRandomNumberGenerator.swift
//  SolidPDF
//
//  Created by Kevin Wooten on 8/15/26.
//

/// The deterministic pseudo-random number generator used by PostScript's random operators.
struct PostScriptRandomNumberGenerator: RandomNumberGenerator {

  private(set) var seed: Int
  private var state: UInt64

  init(seed: Int) {
    self.seed = seed
    self.state = UInt64(bitPattern: Int64(seed))
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }
}
