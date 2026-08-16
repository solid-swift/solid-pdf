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
    try nextScanned(context: context)?.object
  }

  func nextScanned(context: isolated Context) throws -> ScannedObject? {
    try scanner.nextObject(context: context)
  }

  func nextContextual(context: isolated Context) async throws -> ScannedObject? {
    try await scanner.nextContextualObject(context: context)
  }
}
