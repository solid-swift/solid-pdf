import Testing

@testable import SolidPostScript

@Suite struct ImplicitColorResourceTests {
  @Test(arguments: colorSpaceFamilies)
  func colorSpaceFamiliesAreLoadedImplicitResources(name: String) async throws {
    let values = try await Interpreter.results(
      content: "/\(name) /ColorSpaceFamily findresource /\(name) /ColorSpaceFamily resourcestatus"
    )

    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: IntegerValue.self).value == 0)
    #expect(try values[2].value(as: IntegerValue.self).value == 0)
    #expect(try values[3].value(as: NameValue.self).value == name)
  }

  @Test func colorRenderingTypeOneIsLoadedImplicitly() async throws {
    let values = try await Interpreter.results(
      content: "1 /ColorRenderingType findresource 1 /ColorRenderingType resourcestatus"
    )

    #expect(try values[0].value(as: BooleanValue.self).value)
    #expect(try values[1].value(as: IntegerValue.self).value == 0)
    #expect(try values[2].value(as: IntegerValue.self).value == 0)
    #expect(try values[3].value(as: IntegerValue.self).value == 1)
  }

  @Test func namedResourcesEnumerateDeterministicallyUsingPLRMTemplates() throws {
    let resources = NameImplicitResources(category: "ColorSpaceFamily", values: Set(Self.colorSpaceFamilies))

    let all = try resources.enumerateResources(matching: "*")
    #expect(try names(in: all) == Self.colorSpaceFamilies.sorted())

    let device = try resources.enumerateResources(matching: "Device*")
    #expect(try names(in: device) == ["DeviceCMYK", "DeviceGray", "DeviceN", "DeviceRGB"])

    let based = try resources.enumerateResources(matching: "CIEBased?")
    #expect(try names(in: based) == ["CIEBasedA"])
  }

  @Test func unknownAndWronglyTypedInstancesRemainUnavailable() async throws {
    let values = try await Interpreter.results(
      content:
        "/Unknown /ColorSpaceFamily resourcestatus 1 /ColorSpaceFamily resourcestatus 2 /ColorRenderingType resourcestatus"
    )

    #expect(try values[0].value(as: BooleanValue.self).value == false)
    #expect(try values[1].value(as: BooleanValue.self).value == false)
    #expect(try values[2].value(as: BooleanValue.self).value == false)
  }

  @Test(arguments: ["defineresource", "undefineresource"])
  func implicitColorResourcesCannotBeMutated(operation: String) async throws {
    let program: String
    if operation == "defineresource" {
      program = "{ /Extra /Extra /ColorSpaceFamily defineresource } stopped pop $error /errorname get"
    } else {
      program = "{ /DeviceRGB /ColorSpaceFamily undefineresource } stopped pop $error /errorname get"
    }

    let error: NameValue = try await Interpreter.result(content: program)
    #expect(error.value == "invalidaccess")
  }

  @Test func environmentOverridesReplaceTheStandardProvider() async throws {
    let environment = InterpreterEnvironment(resourceCategories: [
      "ColorSpaceFamily": NameImplicitResources(category: "ColorSpaceFamily", values: ["Custom"]),
    ])
    let values = try await Interpreter.results(
      content: "/Custom /ColorSpaceFamily findresource /DeviceRGB /ColorSpaceFamily resourcestatus",
      environment: environment
    )

    #expect(try values[0].value(as: BooleanValue.self).value == false)
    #expect(try values[1].value(as: NameValue.self).value == "Custom")
  }

  @Test func sharedEnvironmentSupportsConcurrentImplicitLookups() async throws {
    let environment = InterpreterEnvironment()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for name in Self.colorSpaceFamilies {
        group.addTask {
          let value: NameValue = try await Interpreter.result(
            content: "/\(name) /ColorSpaceFamily findresource",
            environment: environment
          )
          #expect(value.value == name)
        }
      }
      try await group.waitForAll()
    }
  }

  private static let colorSpaceFamilies = [
    "DeviceGray", "DeviceRGB", "DeviceCMYK",
    "CIEBasedA", "CIEBasedABC", "CIEBasedDEF", "CIEBasedDEFG",
    "Indexed", "Separation", "DeviceN", "Pattern",
  ]

  private func names(in objects: [Object]) throws -> [String] {
    try objects.map { try $0.value(as: NameValue.self).value }
  }
}
