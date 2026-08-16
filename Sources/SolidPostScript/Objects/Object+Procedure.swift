//
//  Object+Procedure.swift
//

import Foundation

extension Object {

  var isProcedure: Bool {
    kind == .executable && (value is ArrayValue || value is PackedArrayValue)
  }

  func checkProcedure() throws {
    guard isProcedure else {
      throw Error.typeCheck
    }
  }

}
