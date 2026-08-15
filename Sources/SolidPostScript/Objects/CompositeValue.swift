//
//  CompositeValue.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// A PostScript composite value.
public protocol CompositeValue: UpdatableAccessValue, RestorableValue {

  var vm: VM { get }

}
