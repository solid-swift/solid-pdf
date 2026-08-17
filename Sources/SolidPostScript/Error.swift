//
//  Error.swift
//
//
//  Created by Kevin Wooten on 6/27/24.
//

import Foundation

/// An error reported while scanning or executing PostScript.
public enum Error: Swift.Error, Equatable, Sendable {

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

  /// A device configuration request cannot be satisfied.
  case configurationError
  /// A dictionary cannot accept another entry.
  case dictionaryFull

  case syntaxError
  case invalidAccess
  case invalidContext
  case invalidExit
  case invalidFileAccess
  case invalidFont
  case invalidId
  case invalidRestore

  case ioError
  /// An external interrupt request occurred.
  case interrupt

  case stackOverflow
  case stackUnderflow

  case dictionaryStackOverflow
  case dictionaryStackUnderflow

  case executionStackOverflow

  case unmatchedMmark
  /// The current graphics path has no current point.
  case noCurrentPoint

  case limitCheck
  case rangeCheck
  case typeCheck

  case undefined
  case undefinedResource
  case undefinedResult
  case undefinedFilename

  case timeout
  /// PostScript virtual memory is exhausted.
  case vmError

  case control(Control)
}

extension Error {

  static let registeredPostScriptNames = [
    "configurationerror",
    "dictfull",
    "dictstackoverflow",
    "dictstackunderflow",
    "execstackoverflow",
    "interrupt",
    "invalidaccess",
    "invalidcontext",
    "invalidexit",
    "invalidfileaccess",
    "invalidfont",
    "invalidid",
    "invalidrestore",
    "ioerror",
    "limitcheck",
    "nocurrentpoint",
    "rangecheck",
    "stackoverflow",
    "stackunderflow",
    "syntaxerror",
    "timeout",
    "typecheck",
    "undefined",
    "undefinedfilename",
    "undefinedresource",
    "undefinedresult",
    "unmatchedmark",
    "unregistered",
    "VMerror",
  ]

  var postScriptName: String? {
    switch self {
    case .configurationError:
      "configurationerror"
    case .dictionaryFull:
      "dictfull"
    case .dictionaryStackOverflow:
      "dictstackoverflow"
    case .dictionaryStackUnderflow:
      "dictstackunderflow"
    case .executionStackOverflow:
      "execstackoverflow"
    case .interrupt:
      "interrupt"
    case .invalidAccess:
      "invalidaccess"
    case .invalidContext:
      "invalidcontext"
    case .invalidExit:
      "invalidexit"
    case .invalidFileAccess:
      "invalidfileaccess"
    case .invalidFont:
      "invalidfont"
    case .invalidId:
      "invalidid"
    case .invalidRestore:
      "invalidrestore"
    case .ioError:
      "ioerror"
    case .limitCheck:
      "limitcheck"
    case .noCurrentPoint:
      "nocurrentpoint"
    case .rangeCheck:
      "rangecheck"
    case .stackOverflow:
      "stackoverflow"
    case .stackUnderflow:
      "stackunderflow"
    case .syntaxError:
      "syntaxerror"
    case .timeout:
      "timeout"
    case .typeCheck:
      "typecheck"
    case .undefined:
      "undefined"
    case .undefinedFilename:
      "undefinedfilename"
    case .undefinedResource:
      "undefinedresource"
    case .undefinedResult:
      "undefinedresult"
    case .unmatchedMmark:
      "unmatchedmark"
    case .unregistered:
      "unregistered"
    case .vmError:
      "VMerror"
    case .control:
      nil
    }
  }

  var isExternal: Bool {
    switch self {
    case .interrupt, .timeout:
      true
    default:
      false
    }
  }
}
