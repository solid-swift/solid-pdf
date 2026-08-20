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
    let resolutionValue = try readOnlyArray([
      try Object.real(configuration.descriptor.horizontalResolution),
      try Object.real(configuration.descriptor.verticalResolution),
    ], vm: vm)
    for profile in session.outputDeviceProfiles {
      let automaticSizes = profile.inputMedia.sources.values.compactMap { source -> GraphicsSize? in
        guard !source.isManual else { return nil }
        return source.attributes?.pageSize
      }
      let manualSizes = profile.inputMedia.sources.values.compactMap { source -> GraphicsSize? in
        guard source.isManual else { return nil }
        return source.attributes?.pageSize
      }
      let pageSizes = try sizeArray(
        automaticSizes.isEmpty ? [configuration.pageSize] : automaticSizes,
        vm: vm
      )
      let manual = try sizeArray(manualSizes, vm: vm)
      let resolutions = try readOnlyArray([resolutionValue], vm: vm)
      let mediaClasses = Set(profile.inputMedia.sources.values.compactMap { $0.attributes?.mediaClass })
      let classArray = try readOnlyArray(
        mediaClasses.sorted { $0.lexicographicallyPrecedes($1) }.map {
          .string($0, access: .readOnly, vm: vm, kind: .literal)
        },
        vm: vm
      )
      let deviceNSets: Object
      if configuration.colorants.processModel == .deviceN {
        let names = try readOnlyArray(
          configuration.colorants.additionalColorants.map { .literalName($0.name) },
          vm: vm
        )
        deviceNSets = try readOnlyArray([names], vm: vm)
      } else {
        deviceNSets = try readOnlyArray([], vm: vm)
      }
      let resource = try makeDictionary([
        (.literalName("OutputDeviceName"), .string(profile.resourceName, access: .readOnly, vm: vm, kind: .literal)),
        (.literalName("MediaClass"), classArray),
        (.literalName("PageSize"), pageSizes),
        (.literalName("ManualSize"), manual),
        (.literalName("HWResolution"), resolutions),
        (.literalName("ProcessColorModel"), processModels),
        (.literalName("DeviceN"), deviceNSets),
        (.literalName("MaxSeparations"), .integer(Int32(clamping: configuration.colorants.maximumSeparations))),
        (.literalName("TrappingDetailsType"), trappingTypes),
      ], access: .readOnly, vm: vm)
      let entry = ResourceEntry(instance: resource, origin: .automatic, size: -1)
      try localResources.define(
        entry,
        for: .literalName(profile.resourceName),
        in: .literalName("OutputDevice")
      )
    }
  }

  private func readOnlyArray(_ objects: [Object], vm: VM) throws -> Object {
    try preflightAllocation(bytes: estimatedAllocationSize(count: objects.count, objectType: .array), vm: vm)
    let result = try Object.array(objects, access: .readOnly, vm: vm, kind: .literal)
    try adopt(result)
    return result
  }

  private func sizeArray(_ sizes: [GraphicsSize], vm: VM) throws -> Object {
    let values = try sizes.map { size in
      try readOnlyArray([try Object.real(size.width), try Object.real(size.height)], vm: vm)
    }
    return try readOnlyArray(values, vm: vm)
  }
}
