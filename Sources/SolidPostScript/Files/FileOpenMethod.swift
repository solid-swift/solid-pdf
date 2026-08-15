//
//  FileOpenMode.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation

/// A PostScript file open method.
public enum FileOpenMethod: Sendable {
  case existingOnly
  case appendExistingOrCreate
  case truncateOrCreate
}

extension FileOpenMethod {

  /// Creates an instance.
  public init(string: String) throws {
    self =
      switch string {
      case "r", "r+": .existingOnly
      case "w", "w+": .truncateOrCreate
      case "a", "a+": .appendExistingOrCreate
      default: throw Error.invalidFileAccess
      }
  }

}
