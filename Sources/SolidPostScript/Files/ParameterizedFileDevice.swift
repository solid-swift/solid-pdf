import Foundation

/// A file device that exposes product-specific PostScript device parameters.
public protocol ParameterizedFileDevice: FileDevice {
  /// Returns a snapshot of the device's current parameter values.
  func currentParameters() throws -> [Object: Object]

  /// Atomically applies the supplied device parameter values.
  func setParameters(_ parameters: [Object: Object]) throws
}
