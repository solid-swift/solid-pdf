//
//  AccessedValue.swift
//
//
//  Created by Kevin Wooten on 7/4/24.
//

import Foundation

/// An PostScript accessed value.
public protocol AccessedValue: ObjectValue {

  var access: ObjectAccess { get }
  mutating func reduceAccess(to reducedAccess: ObjectAccess) throws

}
