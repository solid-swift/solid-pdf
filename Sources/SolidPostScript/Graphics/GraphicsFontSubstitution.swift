/// Evidence describing a font-provider substitution selected for one PDF font.
public struct GraphicsFontSubstitution: Sendable, Hashable {
  /// The PostScript font name requested by the PDF.
  public let requestedName: String
  /// The PostScript font name supplied by the provider, when known.
  public let resolvedName: String?
  /// The provider that supplied the replacement face.
  public let providerIdentifier: String
  /// Whether the provider proved CID collection and selection compatibility.
  public let isCIDCompatible: Bool

  /// Creates substitution metadata.
  public init(
    requestedName: String,
    resolvedName: String? = nil,
    providerIdentifier: String,
    isCIDCompatible: Bool = false
  ) {
    self.requestedName = requestedName
    self.resolvedName = resolvedName
    self.providerIdentifier = providerIdentifier
    self.isCIDCompatible = isCIDCompatible
  }
}
