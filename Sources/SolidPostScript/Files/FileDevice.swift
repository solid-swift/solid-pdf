//
//  FileDevice.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

/// A device capable of opening PostScript files.
public protocol FileDevice: Sendable {

  typealias OpenMethod = FileOpenMethod

  var searched: Bool { get }
  var name: String { get }

  func `open`(name: String, mode: File.Mode, openMethod: OpenMethod) throws -> File

}
