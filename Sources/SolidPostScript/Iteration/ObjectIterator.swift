//
//  ObjectIterator.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An iterator that supplies objects to an interpreter context.
public protocol ObjectIterator: AnyObject {

  func next(context: isolated Context) throws -> Object?

}
