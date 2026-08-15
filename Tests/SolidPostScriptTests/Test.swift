//
//  Test.swift
//  TPPackages
//
//  Created by Kevin Wooten on 12/24/24.
//

import Testing

private enum TestSupportError: Swift.Error {
  case requiredValueMissing
}

func expectEqual<Value: Equatable>(
  _ actual: @autoclosure () throws -> Value,
  _ expected: @autoclosure () throws -> Value,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    let actual = try actual()
    let expected = try expected()
    let message = message()
    #expect(
      actual == expected,
      Comment(rawValue: message.isEmpty ? "Expected \(actual) to equal \(expected)" : message),
      sourceLocation: sourceLocation
    )
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func expectEqual<Value: FloatingPoint>(
  _ actual: @autoclosure () throws -> Value,
  _ expected: @autoclosure () throws -> Value,
  accuracy: Value,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    let actual = try actual()
    let expected = try expected()
    #expect(abs(actual - expected) <= accuracy, sourceLocation: sourceLocation)
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func expectTrue(
  _ condition: @autoclosure () throws -> Bool,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    let message = message()
    #expect(
      try condition(),
      Comment(rawValue: message.isEmpty ? "Expected condition to be true" : message),
      sourceLocation: sourceLocation
    )
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func expectNil(
  _ value: @autoclosure () throws -> Any?,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    let value = try value()
    let message = message()
    #expect(
      value == nil,
      Comment(rawValue: message.isEmpty ? "Expected value to be nil" : message),
      sourceLocation: sourceLocation
    )
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func expectGreaterThanOrEqual<Value: Comparable>(
  _ actual: @autoclosure () throws -> Value,
  _ expected: @autoclosure () throws -> Value,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    #expect(try actual() >= expected(), sourceLocation: sourceLocation)
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func expectLessThanOrEqual<Value: Comparable>(
  _ actual: @autoclosure () throws -> Value,
  _ expected: @autoclosure () throws -> Value,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    #expect(try actual() <= expected(), sourceLocation: sourceLocation)
  } catch {
    Issue.record(error, sourceLocation: sourceLocation)
  }
}

func requireValue<Value>(
  _ value: @autoclosure () throws -> Value?,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Value {
  if let value = try value() {
    return value
  }

  let message = message()
  Issue.record(
    Comment(rawValue: message.isEmpty ? "Expected a non-nil value" : message),
    sourceLocation: sourceLocation
  )
  throw TestSupportError.requiredValueMissing
}

func recordIssue(
  _ message: String = "Recorded an issue",
  sourceLocation: SourceLocation = #_sourceLocation
) {
  Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
