//
//  ErrorHandlingOps.swift
//

import SolidCore

extension Operators {

  static let handleErrorProcedure = neverThrow(
    try Object.array(
      [
        .executableName("errordict"),
        .literalName("handleerror"),
        .executableName("get"),
        .executableName("exec"),
      ],
      access: .readOnly,
      vm: .global,
      kind: .executable
    )
  )
}
