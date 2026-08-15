//
//  NameStringConvertible.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

protocol NameStringConvertible {

  var nameString: String { get }

}

extension NameValue: NameStringConvertible {

  var nameString: String { value }

}

extension StringValue: NameStringConvertible {

  var nameString: String { string }

}
