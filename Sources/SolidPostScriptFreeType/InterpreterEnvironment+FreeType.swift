#if os(Linux)
import SolidPostScript

extension InterpreterEnvironment {
  /// Creates a Linux interpreter environment with FreeType and Fontconfig discovery enabled.
  public static func freeTypeFontconfig(
    hostConfiguration: InterpreterHostConfiguration = InterpreterHostConfiguration(),
    fileDevices: FileDevices = FileDevices(),
    resourceCategories: [Object: any ResourceCategory] = [:]
  ) -> InterpreterEnvironment {
    InterpreterEnvironment(
      hostConfiguration: hostConfiguration,
      fileDevices: fileDevices,
      resourceCategories: resourceCategories,
      fontProviders: [FreeTypeFontProvider()]
    )
  }
}
#endif
