#if canImport(CoreText)
import SolidPostScript

extension InterpreterEnvironment {
  /// Creates an Apple interpreter environment with CoreText host-font discovery enabled.
  public static func coreText(
    hostConfiguration: InterpreterHostConfiguration = InterpreterHostConfiguration(),
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) -> InterpreterEnvironment {
    InterpreterEnvironment(
      hostConfiguration: hostConfiguration,
      fileDevices: fileDevices,
      resourceCategories: resourceCategories,
      fontProviders: [CoreTextFontProvider()]
    )
  }
}
#endif
