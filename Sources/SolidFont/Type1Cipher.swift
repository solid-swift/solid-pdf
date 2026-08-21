/// Incremental state for the cipher shared by Type 1 charstrings and `eexec` data.
package struct Type1CipherState: Sendable {
  package static let charStringSeed: UInt16 = 4_330
  package static let eexecSeed: UInt16 = 55_665

  private static let multiplier: UInt32 = 52_845
  private static let increment: UInt32 = 22_719

  private var state: UInt16

  package init(seed: UInt16) {
    self.state = seed
  }

  package mutating func decrypt(_ ciphertext: UInt8) -> UInt8 {
    let plaintext = ciphertext ^ UInt8(truncatingIfNeeded: state >> 8)
    state = UInt16(
      truncatingIfNeeded: (UInt32(ciphertext) + UInt32(state)) * Self.multiplier + Self.increment
    )
    return plaintext
  }
}
