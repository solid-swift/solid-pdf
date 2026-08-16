//
//  ExecutionStack.swift
//
//
//  Created by Kevin Wooten on 7/5/24.
//

import Foundation
import SolidCore

typealias ExecutionStack = Stack<(source: Object, iterator: ObjectIterator?)>

extension ExecutionStack {

  mutating func push(source: Object, in context: isolated Context) throws {
    try context.adopt(source)
    try (source.value as? any CompositeValue)?.access.check(.execute)
    guard context.stackLimitsBypassed || depth < Int(context.userParameters.integer("MaxExecStack")) else {
      throw Error.executionStackOverflow
    }
    let value = try source.value(as: ObjectSource.self)
    let iterator = try value.makeIterator(context: context)
    push((source, iterator))
  }

}
