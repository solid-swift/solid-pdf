import Foundation

/// A document-scoped identifier for an optional-content group.
public struct PDFOptionalContentGroupIdentifier: Sendable, Hashable, Comparable {
  /// The indirect object containing the group dictionary.
  public let reference: PDFObjectReference

  public init(reference: PDFObjectReference) { self.reference = reference }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.reference < rhs.reference }
}

/// A document-scoped identifier for an optional-content configuration.
public enum PDFOptionalContentConfigurationIdentifier: Sendable, Hashable {
  /// The catalog's default configuration.
  case defaultConfiguration
  /// An alternate configuration at the given zero-based index.
  case alternate(Int)
}

/// The base state applied by an optional-content configuration.
public enum PDFOptionalContentBaseState: Sendable, Hashable {
  case on
  case off
  case unchanged
}

/// A resolved optional-content group.
public struct PDFOptionalContentGroup: Sendable, Hashable {
  public let identifier: PDFOptionalContentGroupIdentifier
  public let name: String
  public let intents: [PDFName]
  public let rawDictionary: [PDFName: PDFObject]
}

/// A resolved optional-content configuration.
public struct PDFOptionalContentConfiguration: Sendable, Hashable {
  public let identifier: PDFOptionalContentConfigurationIdentifier
  public let name: String?
  public let creator: String?
  public let baseState: PDFOptionalContentBaseState
  public let initiallyOn: Set<PDFOptionalContentGroupIdentifier>
  public let initiallyOff: Set<PDFOptionalContentGroupIdentifier>
  public let locked: Set<PDFOptionalContentGroupIdentifier>
  public let rawDictionary: [PDFName: PDFObject]
}

/// The catalog's resolved optional-content properties.
public struct PDFOptionalContentProperties: Sendable, Hashable {
  public let groups: [PDFOptionalContentGroup]
  public let defaultConfiguration: PDFOptionalContentConfiguration
  public let alternateConfigurations: [PDFOptionalContentConfiguration]
}

/// A caller-selected optional-content group state.
public enum PDFOptionalContentState: Sendable, Hashable {
  case on
  case off
}

/// Selection used when evaluating optional content.
public enum PDFOptionalContentSelection: Sendable, Hashable {
  case documentDefault
  case configuration(PDFOptionalContentConfigurationIdentifier)
  case custom(
    base: PDFOptionalContentConfigurationIdentifier,
    overrides: [PDFOptionalContentGroupIdentifier: PDFOptionalContentState]
  )
}

/// The intended use of an optional-content configuration.
public enum PDFOptionalContentUsagePurpose: Sendable, Hashable {
  case view
  case print
  case export
}

/// Environment used to evaluate optional-content usage applications.
public struct PDFOptionalContentContext: Sendable, Hashable {
  public var purpose: PDFOptionalContentUsagePurpose
  public var language: String?
  public var zoom: Double?

  public init(
    purpose: PDFOptionalContentUsagePurpose = .view,
    language: String? = nil,
    zoom: Double? = nil
  ) {
    self.purpose = purpose
    self.language = language
    self.zoom = zoom
  }
}

/// The result of evaluating an optional-content group or membership dictionary.
public struct PDFOptionalContentVisibility: Sendable, Hashable {
  public let isVisible: Bool
  public let controllingGroups: [PDFOptionalContentGroupIdentifier]
}
