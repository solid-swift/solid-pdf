//
//  Error.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An error reported while scanning or executing PostScript.
public enum Error: Swift.Error, Equatable {

  /// An PostScript internal interpreter error.
  public enum InternalInterpreterError: Equatable, Sendable {
    case modeNotDeferred
    case breakExpected
    case stringEncodingUnsupported
    case internalScannerError
  }

  /// A PostScript control.
  public enum Control: Equatable, Sendable {

    // Standard
    case exit
    case stop
    case quit

    // Implementation
    case `break`
  }

  case unregistered(InternalInterpreterError)

  case syntaxError
  case invalidAccess
  case invalidContext
  case invalidExit
  case invalidFileAccess
  case invalidFont
  case invalidId
  case invalidRestore

  case ioError

  case stackOverflow
  case stackUnderflow

  case dictionaryStackOverflow
  case dictionaryStackUnderflow

  case executionStackOverflow

  case unmatchedMmark

  case limitCheck
  case rangeCheck
  case typeCheck

  case undefined
  case undefinedResource
  case undefinedResult
  case undefinedFilename

  case timeout

  case control(Control)
}
