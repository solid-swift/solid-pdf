//
//  UndispatchedError.swift
//

import Foundation

/// Carries an error that cannot be dispatched through a damaged `errordict`.
struct UndispatchedError: Swift.Error {
  let error: Error
}
