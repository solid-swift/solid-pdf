import Foundation
import SolidFont

enum PDFPredefinedCMaps {
  static func characterMap(
    named name: String,
    limits: PDFGraphicsLimits,
    visited: Set<String> = []
  ) throws -> PDFCMap {
    if name == "Identity-H" { return .identity(vertical: false) }
    if name == "Identity-V" { return .identity(vertical: true) }
    guard !visited.contains(name), visited.count < limits.maximumResourceDepth else {
      throw PDFCMapError.limitExceeded
    }
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
      throw PDFCMapError.malformed
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    var map = try PDFCMapParser(
      maximumBytes: limits.maximumCMapBytes,
      maximumEntries: limits.maximumCMapEntries
    ).parse(data)
    var nextVisited = visited
    nextVisited.insert(name)
    for baseName in map.useCMapNames {
      try map.inherit(
        characterMap(named: baseName, limits: limits, visited: nextVisited),
        maximumEntries: limits.maximumCMapEntries
      )
    }
    return map
  }

  static func unicodeMap(
    for systemInfo: FontCIDSystemInfo,
    limits: PDFGraphicsLimits
  ) throws -> PDFCMap? {
    guard systemInfo.registry == "Adobe" else { return nil }
    let resourceName = "Adobe-\(systemInfo.ordering)-UCS2"
    guard let url = Bundle.module.url(forResource: resourceName, withExtension: nil) else { return nil }
    return try PDFCMapParser(
      maximumBytes: limits.maximumCMapBytes,
      maximumEntries: limits.maximumCMapEntries
    ).parse(Data(contentsOf: url, options: .mappedIfSafe))
  }
}
