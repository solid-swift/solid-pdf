//
//  Datas.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Data {

  internal static func < (_ lhs: Data, _ rhs: Data) -> ComparisonResult {

    let minLength = Swift.min(lhs.count, rhs.count)

    for i in 0..<minLength {
      if lhs[i] < rhs[i] {
        return .orderedAscending
      } else if lhs[i] > rhs[i] {
        return .orderedDescending
      }
    }

    if lhs.count < rhs.count {
      return .orderedAscending
    } else if lhs.count > rhs.count {
      return .orderedDescending
    } else {
      return .orderedSame
    }
  }
}
