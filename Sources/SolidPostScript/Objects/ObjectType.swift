//
//  ObjectType.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An PostScript object type.
public struct ObjectType: Equatable, Hashable, Sendable {
  /// The ``name`` value.
  public var name: String

  /// Creates an instance.
  public init(_ name: String) {
    self.name = name
  }

  // Simple
  /// The ``null`` value.
  public static let null = Self("nulltype")
  /// The ``boolean`` value.
  public static let boolean = Self("booleantype")
  /// The ``integer`` value.
  public static let integer = Self("integertype")
  /// The ``real`` value.
  public static let real = Self("realtype")
  /// The ``name`` value.
  public static let name = Self("nametype")

  /// The ``operator`` value.
  public static let `operator` = Self("operatortype")

  /// The ``mark`` value.
  public static let mark = Self("marktype")
  /// The ``save`` value.
  public static let save = Self("savetype")

  /// The ``lock`` value.
  public static let lock = Self("locktype")
  /// The ``condition`` value.
  public static let condition = Self("conditiontype")

  // Composite
  /// The ``string`` value.
  public static let string = Self("stringtype")
  /// The ``array`` value.
  public static let array = Self("arraytype")
  /// The ``packedArray`` value.
  public static let packedArray = Self("packedarraytype")
  /// The ``dictionary`` value.
  public static let dictionary = Self("dicttype")
  /// The ``file`` value.
  public static let file = Self("filetype")

  // Graphics
  /// The ``graphicsState`` value.
  public static let graphicsState = Self("gstatetype")
  /// The ``fontID`` value.
  public static let fontID = Self("fonttype")

}

extension ObjectType: CustomStringConvertible {

  /// The ``description`` value.
  public var description: String { name }

}
