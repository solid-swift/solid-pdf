import Foundation

final class FontManager: Sendable {
  let providers: [any FontResourceProvider]
  let glyphCache = FontGlyphCache()
  let outlineCache = FontOutlineCache()

  init(providers: [any FontResourceProvider]) {
    self.providers = providers
  }

  func provider(identifier: String) -> (any FontResourceProvider)? {
    providers.first { $0.identifier == identifier }
  }
}
