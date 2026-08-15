//
//  ObjectSource.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// A value that can create an iterator of PostScript objects.
public protocol ObjectSource: ObjectValue {

  func makeIterator(context: isolated Context) throws -> ObjectIterator

}
