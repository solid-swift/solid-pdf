//
//  TokenObjectIterator.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// A PostScript token object iterator.
public class TokenObjectIterator: ObjectIterator {

  let scanner: Scanner

  /// Creates an instance.
  public init(scanner: Scanner) {
    self.scanner = scanner
  }

  /// Returns the next PostScript object, when available.
  public func next(context: isolated Context) throws -> Object? {

    guard let token = try scanner.nextToken() else {
      return nil
    }

    return switch token {
    case .integer(let int): int.numericObject
    case .real(let real): real.numericObject
    case .string(let string):
      .string(string, access: .unlimited, vm: .local, kind: .literal)
    case .name(let name, kind: let kind):
      if name.starts(with: "/") {
        try NameValue(value: String(name.dropFirst())).lookup(in: context)
      } else {
        .name(name, kind: kind)
      }
    }
  }
}
