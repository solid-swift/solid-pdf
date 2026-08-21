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
  func inventoryMatchesAdvertisedResourceCategoriesAndInstances() async throws {
    let inventory = try Inventory.load()
    let environment = InterpreterEnvironment()
    var actualCategories = Set(try environment.resourceCategories.keys.map(Self.name))
    actualCategories.insert("Generic")

    #expect(actualCategories == Set(inventory.resources.categories))
    for (category, instances) in inventory.resources.implicitImplemented {
      let resourceCategory = try environment.resourceCategory(for: .literalName(category))
      let provider = try #require(resourceCategory)
      let actual = try provider.enumerateResources(matching: "*").map {
        try $0.value(as: IntegerValue.self).value
      }
      #expect(actual == instances.sorted(), "Unexpected implicit /\(category) resources")
    }

    for (category, instances) in inventory.resources.namedImplemented {
      let actual = try await Self.resourceNames(in: category, environment: environment)
      #expect(actual == Set(instances), "Unexpected named /\(category) resources")
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
    #expect(inventory.parameters.systemNonconforming.isEmpty)
    #expect(
      Set(inventory.errors.standardImplemented + inventory.errors.extensionsImplemented)
        == Set(Error.registeredPostScriptNames)
    )
  }

  @Test
  func inventoryClassificationsAndEvidenceAreWellFormed() throws {
    let inventory = try Inventory.load()
    #expect(inventory.schemaVersion == 2)
    #expect(Set(inventory.classifications) == ["implemented", "intentionally-unavailable", "postponed", "nonconforming"])
    #expect(inventory.standardFiles.map(\.name) == ["%stdin", "%stdout", "%stderr", "%lineedit", "%statementedit"])
    #expect(inventory.standardFiles.allSatisfy { $0.status == "implemented" })
    #expect(inventory.operators.nonconforming.isEmpty)
    #expect(inventory.resources.nonconforming.isEmpty)
    #expect(inventory.parameters.systemNonconforming.isEmpty)
    #expect(inventory.errors.nonconforming.isEmpty)
    #expect(inventory.languageLevelRequirements.allSatisfy { $0.status == "implemented" })
    #expect(
      inventory.languageLevelRequirements.map(\.name).count
        == Set(inventory.languageLevelRequirements.map(\.name)).count
    )

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
    evidence.append(contentsOf: inventory.languageLevelRequirements.flatMap(\.registration))
    evidence.append(contentsOf: inventory.languageLevelRequirements.flatMap(\.tests))
    evidence.append(contentsOf: inventory.standardFiles.map(\.evidence))

    for path in evidence {
      #expect(FileManager.default.fileExists(atPath: Inventory.repositoryRoot.appending(path: path).path))
    }
  }

  @Test
  func semanticLedgerCoversEveryOperatorMissingFromTheOriginalAuditVectors() throws {
    let inventory = try Inventory.load()
    let operators = Set(inventory.languageLevelRequirements.flatMap(\.operators))

    #expect(operators == Self.auditedSemanticOperators)
    for requirement in inventory.languageLevelRequirements where !requirement.operators.isEmpty {
      #expect(requirement.tests.contains("Tests/SolidPostScriptTests/PLRMSemanticOperatorTests.swift"))
    }
  }

  private static func name(_ object: Object) throws -> String {
    try object.value(as: NameValue.self).value
  }

  private static func resourceNames(
    in category: String,
    environment: InterpreterEnvironment
  ) async throws -> Set<String> {
    let values: ArrayValue = try await Interpreter.result(
      content:
        """
        /names 100 array def /count 0 def
        (*) { names count 3 -1 roll cvn put /count count 1 add store }
        100 string /\(category) resourceforall
        names 0 count getinterval
        """,
      environment: environment
    )
    return try Set(values.objects(in: values.range).map(Self.name))
  }

  private static let auditedSemanticOperators: Set<String> = [
    "arcn", "ashow", "awidthshow", "concatmatrix", "currentblackgeneration",
    "currentcolorscreen", "currentcolortransfer", "currenthsbcolor", "currentundercolorremoval",
    "defaultmatrix", "eoclip", "erasepage", "findencoding", "glyphshow", "grestoreall",
    "identmatrix", "inueofill", "invertmatrix", "rcurveto", "rectstroke", "rootfont", "rotate",
    "selectfont", "setcachedevice2", "setcacheparams", "setcolortransfer", "sethsbcolor", "setmatrix",
    "setvmthreshold", "ueofill", "widthshow", "xshow", "xyshow", "yshow",
  ]
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
    let systemNonconforming: [NamedReason]
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
    let nonconforming: [NamedReason]
    let evidence: [String]
  }

  struct Requirement: Decodable {
    let name: String
    let status: String
    let operators: [String]
    let registration: [String]
    let tests: [String]

    private enum CodingKeys: String, CodingKey {
      case name
      case status
      case operators
      case registration
      case tests
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try container.decode(String.self, forKey: .name)
      status = try container.decode(String.self, forKey: .status)
      operators = try container.decodeIfPresent([String].self, forKey: .operators) ?? []
      registration = try container.decode([String].self, forKey: .registration)
      tests = try container.decode([String].self, forKey: .tests)
    }
  }

  let schemaVersion: Int
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
