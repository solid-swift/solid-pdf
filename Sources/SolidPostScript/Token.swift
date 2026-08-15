//
//  Token.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// A lexical token recognized in PostScript source.
public enum Token: Equatable, Hashable {
  case integer(Int)
  case real(Double)
  case string(Data)
  case name(String, kind: ObjectKind)
}

extension Token: CustomStringConvertible {

  /// The ``description`` value.
  public var description: String {
    switch self {
    case .integer(let int): "\(int)"
    case .real(let real): "\(real)"
    case .name(let name, kind: let kind): kind == .literal ? "/\(name)" : name
    case .string(let data): String(data: data, encoding: .symbol) ?? "<non-printable>"
    }
  }

}
