import Foundation

enum LanguageLimits {
  static let maximumNameLength = 127

  static func validateNameLength(_ length: Int) throws {
    guard length <= maximumNameLength else {
      throw Error.limitCheck
    }
  }

  static func validateName(_ name: String) throws {
    guard let data = name.data(using: .isoLatin1) else {
      throw Error.limitCheck
    }
    try validateNameLength(data.count)
  }
}
