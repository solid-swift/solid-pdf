//
//  PostScriptOperators.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation


/// An PostScript operators.
public enum Operators {

  /// The ``all`` value.
  public static let all: [OperatorValue] =
    stackOps + deferOps + controlOps + attributeOps + conversionOps + procedureOps + polymorphicOps + collectionOps
    + arrayOps + packedArrayOps + dictionaryOps + stringOps + arithmeticOps + trigonometricOps + mathOps + randomOps
    + relationalOps + logicalBitwiseOps + fileOps + binaryObjectOps + filterOps + resourceOperators + timeOps + vmOps
    + userObjectsOps

}
