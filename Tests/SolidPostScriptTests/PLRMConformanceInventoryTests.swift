import Foundation
import Testing

@testable import SolidPostScript

@Suite
struct PLRMConformanceInventoryTests {

  @Test
  func inventoryCoversEveryRegisteredOperatorAndSystemBinding() async throws {
    let inventory = try Inventory.load()
    let documentedOperators = Set(
      inventory.operators.systemDictionaryImplemented + inventory.operators.privateImplementation
    )
    let registeredOperators = Set(try Operators.all.flatMap { value in
      try value.systemDictionaryNames.map(Self.name)
    })

    #expect(registeredOperators.isSubset(of: documentedOperators))
    #expect(inventory.operators.systemDictionaryImplemented.count == Set(inventory.operators.systemDictionaryImplemented).count)
    #expect(inventory.operators.privateImplementation.count == Set(inventory.operators.privateImplementation).count)

    let systemDictionary: DictionaryValue = try await Interpreter.result(content: "systemdict")
    let conditionalNames = Set(inventory.operators.conditionalSystemDictionary)
    for name in inventory.operators.systemDictionaryImplemented + inventory.operators.systemDictionaryBindings {
      if conditionalNames.contains(name) { continue }
      #expect(try systemDictionary.object(forKeyIfExists: .literalName(name)) != nil, "Missing systemdict /\(name)")
    }
    for unavailable in inventory.operators.intentionallyUnavailable + inventory.operators.nonconforming {
      #expect(try systemDictionary.object(forKeyIfExists: .literalName(unavailable.name)) == nil)
    }
  }

  @Test
  func inventoryCoversProcedureSetOperators() async throws {
    let inventory = try Inventory.load()

    for procSet in inventory.operators.procedureSets {
      let dictionary: DictionaryValue = try await Interpreter.result(
        content: "/\(procSet.name) /ProcSet findresource"
      )
      for name in procSet.operators {
        #expect(try dictionary.object(forKey: .literalName(name)).type != .null)
      }
    }
  }

  @Test
  func inventoryMatchesAdvertisedResourceCategoriesAndInstances() throws {
    let inventory = try Inventory.load()
    let environment = InterpreterEnvironment()
    var actualCategories = Set(try environment.resourceCategories.keys.map(Self.name))
    actualCategories.insert("Generic")

    #expect(actualCategories == Set(inventory.resources.categories))
    #expect(Set(Operators.Filter.availableNames) == Set(inventory.resources.namedImplemented["Filter", default: []]))

    for (category, instances) in inventory.resources.implicitImplemented {
      let resourceCategory = try environment.resourceCategory(for: .literalName(category))
      let provider = try #require(resourceCategory)
      for instance in instances {
        #expect(try provider.statusOfResource(forKey: .integer(instance)) != nil)
      }
    }

    for gap in inventory.resources.nonconforming {
      let resourceCategory = try environment.resourceCategory(for: .literalName(gap.category))
      let provider = try #require(resourceCategory)
      for instance in gap.instances {
        let key: Object = switch instance {
        case .integer(let value): .integer(value)
        case .string(let value): .literalName(value)
        }
        #expect(try provider.statusOfResource(forKey: key) == nil)
      }
    }
  }

  @Test
  func inventoryMatchesInterpreterParametersAndErrors() throws {
    let inventory = try Inventory.load()

    #expect(Set(inventory.parameters.userImplemented) == Set(UserParameterState.definitions.keys))
    #expect(Set(inventory.parameters.systemImplemented) == Set(SystemParameterState.definitions.keys))
    #expect(
      Set(inventory.errors.standardImplemented + inventory.errors.extensionsImplemented)
        == Set(Error.registeredPostScriptNames)
    )
  }

  @Test
  func inventoryClassificationsAndEvidenceAreWellFormed() throws {
    let inventory = try Inventory.load()
    #expect(Set(inventory.classifications) == ["implemented", "intentionally-unavailable", "postponed", "nonconforming"])
    #expect(inventory.standardFiles.map(\.name) == ["%stdin", "%stdout", "%stderr", "%lineedit", "%statementedit"])
    #expect(inventory.standardFiles.allSatisfy { $0.status == "implemented" })

    var evidence = [
      inventory.authority.source,
      inventory.operators.evidence.registration,
      inventory.operators.evidence.systemDictionary,
      inventory.parameters.evidence.user,
      inventory.parameters.evidence.system,
      inventory.parameters.evidence.device,
      inventory.parameters.evidence.pageDevice,
    ]
    evidence.append(contentsOf: inventory.resources.evidence.registration)
    evidence.append(contentsOf: inventory.errors.evidence)
    evidence.append(contentsOf: inventory.languageLevelRequirements.map(\.evidence))
    evidence.append(contentsOf: inventory.standardFiles.map(\.evidence))

    for path in evidence {
      #expect(FileManager.default.fileExists(atPath: Inventory.repositoryRoot.appending(path: path).path))
    }
  }

  private static func name(_ object: Object) throws -> String {
    try object.value(as: NameValue.self).value
  }
}

private struct Inventory: Decodable {
  struct Authority: Decodable {
    let source: String
  }

  struct NamedReason: Decodable {
    let name: String
  }

  struct OperatorEvidence: Decodable {
    let registration: String
    let systemDictionary: String
  }

  struct ProcedureSet: Decodable {
    let name: String
    let operators: [String]
  }

  struct Operators: Decodable {
    let systemDictionaryImplemented: [String]
    let systemDictionaryBindings: [String]
    let conditionalSystemDictionary: [String]
    let privateImplementation: [String]
    let procedureSets: [ProcedureSet]
    let intentionallyUnavailable: [NamedReason]
    let nonconforming: [NamedReason]
    let evidence: OperatorEvidence
  }

  enum ResourceInstance: Decodable {
    case integer(Int32)
    case string(String)

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let integer = try? container.decode(Int32.self) {
        self = .integer(integer)
      } else {
        self = .string(try container.decode(String.self))
      }
    }
  }

  struct ResourceGap: Decodable {
    let category: String
    let instances: [ResourceInstance]
  }

  struct ResourceEvidence: Decodable {
    let registration: [String]
  }

  struct Resources: Decodable {
    let categories: [String]
    let implicitImplemented: [String: [Int32]]
    let namedImplemented: [String: [String]]
    let nonconforming: [ResourceGap]
    let evidence: ResourceEvidence
  }

  struct ParameterEvidence: Decodable {
    let user: String
    let system: String
    let device: String
    let pageDevice: String
  }

  struct Parameters: Decodable {
    let userImplemented: [String]
    let systemImplemented: [String]
    let evidence: ParameterEvidence
  }

  struct StandardFile: Decodable {
    let name: String
    let status: String
    let evidence: String
  }

  struct Errors: Decodable {
    let standardImplemented: [String]
    let extensionsImplemented: [String]
    let evidence: [String]
  }

  struct Requirement: Decodable {
    let evidence: String
  }

  let authority: Authority
  let classifications: [String]
  let operators: Operators
  let resources: Resources
  let parameters: Parameters
  let standardFiles: [StandardFile]
  let errors: Errors
  let languageLevelRequirements: [Requirement]

  static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  static func load() throws -> Self {
    let url = repositoryRoot.appending(path: "Documentation/PLRMConformance.json")
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
}
