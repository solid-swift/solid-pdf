//
//  Datas.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Data {

  internal static func < (_ lhs: Data, _ rhs: Data) -> ComparisonResult {

    for (lhsByte, rhsByte) in zip(lhs, rhs) {
      if lhsByte < rhsByte {
        return .orderedAscending
      } else if lhsByte > rhsByte {
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
