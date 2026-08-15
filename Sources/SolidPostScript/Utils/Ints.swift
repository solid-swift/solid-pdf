//
//  Ints.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Int {

  internal init(checking value: UInt) throws {
    guard let int = Int(exactly: value) else {
      throw Error.rangeCheck
    }
    self = int
  }

  var unsigned: UInt {
    get throws { try UInt(checking: self) }
  }

}

extension UInt {

  internal init(checking value: Int) throws {
    guard let uint = UInt(exactly: value) else {
      throw Error.rangeCheck
    }
    self = uint
  }

  var signed: Int {
    get throws { try Int(checking: self) }
  }

}
