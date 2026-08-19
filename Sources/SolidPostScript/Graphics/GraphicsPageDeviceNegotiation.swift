import Foundation

/// The result of negotiating page settings with a target.
public struct GraphicsPageDeviceNegotiation: Sendable, Hashable {
  /// The actual configuration selected by the target.
  public let configuration: GraphicsPageDeviceConfiguration
  /// Requested parameter names the target could not satisfy.
  public let unsatisfiedParameters: Set<String>

  /// Creates a negotiation result.
  public init(
    configuration: GraphicsPageDeviceConfiguration,
    unsatisfiedParameters: Set<String> = []
  ) {
    self.configuration = configuration
    self.unsatisfiedParameters = unsatisfiedParameters
  }
}
