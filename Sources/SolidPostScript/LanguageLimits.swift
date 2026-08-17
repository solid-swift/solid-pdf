import Foundation

enum LanguageLimits {
  static let maximumNameLength = 127

  static func validateNameLength(_ length: Int) throws {
    guard length <= maximumNameLength else {
      throw Error.limitCheck
    }
  }

  static func validateName(_ name: String) throws {
    let data = try postScriptBytes(name)
    try validateNameLength(data.count)
  }

  static func postScriptBytes(_ value: String) throws -> Data {
    guard let data = value.data(using: .isoLatin1) else {
      throw Error.limitCheck
    }
    return data
  }
}
