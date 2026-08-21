/// One StandardEncoding component referenced by a Type 1 composite charstring.
public struct FontCharStringComponent: Sendable, Hashable {
  /// The StandardEncoding character code of the component glyph.
  public let characterCode: UInt8
  /// The component displacement in glyph coordinates.
  public let offset: FontPoint

  /// Creates a composite charstring component.
  public init(characterCode: UInt8, offset: FontPoint) {
    self.characterCode = characterCode
    self.offset = offset
  }
}
