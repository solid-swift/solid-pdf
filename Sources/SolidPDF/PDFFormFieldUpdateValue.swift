/// A semantic value assigned to one AcroForm field.
public enum PDFFormFieldUpdateValue: Sendable, Hashable {
  /// Assigns Unicode text using an exact PDF text-string representation.
  case text(String)
  /// Assigns caller-provided PDF text-string bytes.
  case encodedText(PDFString)
  /// Selects one or more options by their decoded export values.
  case choice([String])
  /// Selects one or more options by their exact encoded export values.
  case encodedChoice([PDFString])
  /// Selects a checkbox or radio-button appearance state; `nil` means `/Off`.
  case button(PDFName?)
  /// Removes the field's current value.
  case clear
  /// Restores the inherited default value, or clears the field when no default exists.
  case resetToDefault
}
