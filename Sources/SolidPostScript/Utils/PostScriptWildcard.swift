//
//  PostScriptWildcard.swift
//

extension String {

  var asTemplateRegex: Regex<AnyRegexOutput>? {
    asTemplateRegex(pathSeparatorSensitive: false)
  }

  func asTemplateRegex(pathSeparatorSensitive: Bool) -> Regex<AnyRegexOutput>? {
    var pattern = ""
    var escaped = false
    for character in self {
      if escaped {
        pattern.append(character.regexEscaped)
        escaped = false
      } else {
        switch character {
        case "\\":
          escaped = true
        case "*":
          pattern.append(pathSeparatorSensitive ? "[^/]*" : ".*")
        case "?":
          pattern.append(pathSeparatorSensitive ? "[^/]" : ".")
        default:
          pattern.append(character.regexEscaped)
        }
      }
    }
    if escaped {
      pattern.append(#"\\"#)
    }
    return try? Regex(pattern)
  }
}

private extension Character {

  var regexEscaped: String {
    "\\.^$|()[]{}+*?".contains(self) ? "\\\(self)" : String(self)
  }
}
