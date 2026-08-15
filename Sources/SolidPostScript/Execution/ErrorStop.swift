//
//  ErrorStop.swift
//
import Foundation

/// Carries the language error through the default handler's `stop` operation.
struct ErrorStop: Swift.Error {
  let error: Error
}
