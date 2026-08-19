import Foundation

extension Context {
  func installCurrentOutputDeviceResource() throws {
    guard let session = graphicsPageDeviceSession,
      let configuration = graphicsState.device.configuration
    else { return }
    try ensureResourcesInitialized()
    let vm = VM.local
    let trappingTypes = try readOnlyArray(
      session.capabilities.trapping.supportedTypes.sorted().compactMap(Object.integer(exactly:)),
      vm: vm
    )
    let processModels = try readOnlyArray(
      session.capabilities.colorants.supportedProcessModels
        .sorted { $0.rawValue < $1.rawValue }
        .map { .literalName($0.rawValue) },
      vm: vm
    )
    let pageSize = try readOnlyArray([
      try Object.real(configuration.pageSize.width),
      try Object.real(configuration.pageSize.height),
    ], vm: vm)
    let resolution = try readOnlyArray([
      try Object.real(configuration.descriptor.horizontalResolution),
      try Object.real(configuration.descriptor.verticalResolution),
    ], vm: vm)
    let resource = try makeDictionary([
      (.literalName("OutputDeviceName"), .string(configuration.name, access: .readOnly, vm: vm, kind: .literal)),
      (.literalName("PageSize"), pageSize),
      (.literalName("HWResolution"), resolution),
      (.literalName("ProcessColorModels"), processModels),
      (.literalName("MaxSeparations"), .integer(Int32(clamping: configuration.colorants.maximumSeparations))),
      (.literalName("TrappingDetailsType"), trappingTypes),
    ], access: .readOnly, vm: vm)
    let entry = ResourceEntry(instance: resource, origin: .automatic, size: -1)
    try localResources.define(
      entry,
      for: .literalName(configuration.name),
      in: .literalName("OutputDevice")
    )
  }

  private func readOnlyArray(_ objects: [Object], vm: VM) throws -> Object {
    try preflightAllocation(bytes: estimatedAllocationSize(count: objects.count, objectType: .array), vm: vm)
    let result = try Object.array(objects, access: .readOnly, vm: vm, kind: .literal)
    try adopt(result)
    return result
  }
}
