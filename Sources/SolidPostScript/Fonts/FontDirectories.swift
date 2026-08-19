import Foundation

extension Context {
  func fontDirectory(for vm: VM) throws -> DictionaryValue {
    if vm == .global {
      return try environment.globalFontDirectory.value(as: DictionaryValue.self)
    }
    return try dictionaries.systemDictionary().objectValue(forKey: "FontDirectory", as: DictionaryValue.self)
  }
}
