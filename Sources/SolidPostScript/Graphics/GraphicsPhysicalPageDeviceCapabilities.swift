import Foundation

/// Physical media, placement, and delivery features supported by a page device.
public struct GraphicsPhysicalPageDeviceCapabilities: Sendable, Hashable {
  /// Whether input-media matching is supported.
  public let supportsMediaSelection: Bool
  /// Whether media and destination matching may be deferred.
  public let supportsDeferredSelection: Bool
  /// Whether manual feeding is supported.
  public let supportsManualFeed: Bool
  /// Whether automatic tray switching is supported.
  public let supportsTraySwitch: Bool
  /// Whether duplex placement is supported.
  public let supportsDuplex: Bool
  /// Whether mirror output is supported.
  public let supportsMirrorPrint: Bool
  /// Whether negative output is supported.
  public let supportsNegativePrint: Bool
  /// Whether document collation is supported.
  public let supportsCollation: Bool
  /// Whether collated sets may span compatible page-device installations.
  public let supportsCrossDeviceCollation: Bool
  /// Whether roll-media advance and cut actions are supported.
  public let supportsRollMedia: Bool

  /// Creates physical page-device capabilities.
  public init(
    supportsMediaSelection: Bool = false,
    supportsDeferredSelection: Bool = false,
    supportsManualFeed: Bool = false,
    supportsTraySwitch: Bool = false,
    supportsDuplex: Bool = false,
    supportsMirrorPrint: Bool = false,
    supportsNegativePrint: Bool = false,
    supportsCollation: Bool = false,
    supportsCrossDeviceCollation: Bool = false,
    supportsRollMedia: Bool = false
  ) {
    self.supportsMediaSelection = supportsMediaSelection
    self.supportsDeferredSelection = supportsDeferredSelection
    self.supportsManualFeed = supportsManualFeed
    self.supportsTraySwitch = supportsTraySwitch
    self.supportsDuplex = supportsDuplex
    self.supportsMirrorPrint = supportsMirrorPrint
    self.supportsNegativePrint = supportsNegativePrint
    self.supportsCollation = supportsCollation
    self.supportsCrossDeviceCollation = supportsCrossDeviceCollation
    self.supportsRollMedia = supportsRollMedia
  }

  /// Capabilities of a virtual page device.
  public static let virtual = Self()

  /// Capabilities of the portable print-spool device.
  public static let printSpool = Self(
    supportsMediaSelection: true,
    supportsDeferredSelection: true,
    supportsManualFeed: true,
    supportsTraySwitch: true,
    supportsDuplex: true,
    supportsMirrorPrint: true,
    supportsNegativePrint: true,
    supportsCollation: true,
    supportsCrossDeviceCollation: true,
    supportsRollMedia: true
  )
}
