import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFRecoveryTests {
  @Test
  func strictParsingRemainsDefault() async throws {
    let malformed = fixture(startCrossReferenceAdjustment: 7)
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(malformed))
    }
  }

  @Test
  func recoversDisplacedHeaderAndIncorrectStartCrossReference() async throws {
    let malformed = fixture(prefix: Data("leading junk\n".utf8), startCrossReferenceAdjustment: 7)
    let document = try await PDFDocument(
      source: PDFDataInputSource(malformed),
      options: .init(recovery: .init(policy: .structural))
    )
    let report = try #require(document.recoveryReport)
    #expect(report.policy == .structural)
    #expect(report.records.map(\.kind).contains(.header))
    #expect(report.records.map(\.kind).contains(.startCrossReference))
    #expect(try await document.pageCount() == 0)
    await document.close()
  }

  @Test
  func recoversMissingTerminalMarker() async throws {
    var malformed = fixture()
    let marker = Data("%%EOF\n".utf8)
    #expect(malformed.suffix(marker.count) == marker)
    malformed.removeLast(marker.count)
    let document = try await PDFDocument(
      source: PDFDataInputSource(malformed),
      options: .init(recovery: .init())
    )
    let report = try #require(document.recoveryReport)
    #expect(report.records.map(\.kind).contains(.endOfFile))
    await document.close()
  }

  @Test
  func reconstructsIncorrectObjectOffsets() async throws {
    let malformed = fixture(catalogCrossReferenceAdjustment: 3)
    let document = try await PDFDocument(
      source: PDFDataInputSource(malformed),
      options: .init(recovery: .init())
    )
    let report = try #require(document.recoveryReport)
    #expect(report.records.map(\.kind).contains(.crossReference))
    let catalog = try await document.resolve(document.root)
    #expect(catalog.recoveryProvenance != nil)
    #expect(try await document.pageCount() == 0)
    await document.close()
  }

  @Test
  func recoversMissingEndObjectBoundary() async throws {
    let malformed = fixture(omitsCatalogEndObject: true)
    let document = try await PDFDocument(
      source: PDFDataInputSource(malformed),
      options: .init(recovery: .init())
    )
    #expect(document.recoveryReport?.records.map(\.kind).contains(.indirectObject) == true)
    #expect(try await document.pageCount() == 0)
    await document.close()
  }

  @Test
  func recoversIncorrectStreamLengthAndBoundary() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(streamFixture()),
      options: .init(recovery: .init())
    )
    let page = try await document.page(at: 0)
    let stream = try #require(page.contentStreams.first)
    #expect(try await document.decodedBytes(of: stream) == Data("abc endstream xyz".utf8))
    #expect(document.recoveryReport?.records.map(\.kind).contains(.streamBoundary) == true)
    await document.close()
  }

  @Test
  func recoversUniqueCatalogAndMissingTypes() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(structureFixture()),
      options: .init(recovery: .init())
    )
    let expectedRoot = try PDFObjectReference(objectNumber: 1, generationNumber: 0)
    #expect(document.root == expectedRoot)
    #expect(try await document.pageCount() == 0)
    #expect(document.recoveryReport?.records.map(\.kind).contains(.catalog) == true)
    await document.close()
  }

  @Test
  func compatibleRecoveryAdjudicatesDuplicateDefinitions() async throws {
    let malformed = fixture(catalogCrossReferenceAdjustment: 3, duplicatesCatalog: true)
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(malformed),
        options: .init(recovery: .init(policy: .structural))
      )
    }
    let document = try await PDFDocument(
      source: PDFDataInputSource(malformed),
      options: .init(recovery: .init(policy: .compatible))
    )
    let report = try #require(document.recoveryReport)
    #expect(report.records.contains { $0.classification == .semanticInference })
    guard case .ineligible = report.incrementalWriting else {
      Issue.record("Compatibility recovery unexpectedly permitted writing")
      return
    }
    #expect(try await document.pageCount() == 0)
    await document.close()
  }

  @Test
  func rejectsInvalidRecoveryRegistry() throws {
    #expect(throws: PDFParsingError.self) {
      _ = try PDFRecoveryRegistry(passes: [TestRecoveryPass(), TestRecoveryPass()])
    }
    #expect(throws: PDFParsingError.self) {
      _ = try PDFRecoveryRegistry(passes: [BackwardsInvalidatingPass()])
    }
  }

  @Test
  func registryOrdersPassesDeterministically() throws {
    let registry = try PDFRecoveryRegistry(passes: [
      OrderedRecoveryPass(identifier: "b", priority: 1),
      OrderedRecoveryPass(identifier: "a", priority: 1),
      OrderedRecoveryPass(identifier: "z", priority: 0),
    ])
    #expect(registry.passes.map(\.descriptor.identifier) == ["z", "a", "b"])
  }

  @Test
  func enforcesCandidateAndConfigurationLimits() async throws {
    var invalid = PDFRecoveryLimits()
    invalid.maximumPassGenerations = 0
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture(startCrossReferenceAdjustment: 7)),
        options: .init(recovery: .init(limits: invalid))
      )
    }
    var bounded = PDFRecoveryLimits()
    bounded.maximumCandidateObjects = 1
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture(startCrossReferenceAdjustment: 7)),
        options: .init(recovery: .init(limits: bounded))
      )
    }
  }

  private func fixture(
    prefix: Data = Data(),
    startCrossReferenceAdjustment: Int = 0,
    catalogCrossReferenceAdjustment: Int = 0,
    omitsCatalogEndObject: Bool = false,
    duplicatesCatalog: Bool = false
  ) -> Data {
    var data = prefix
    data.append(Data("%PDF-1.7\n".utf8))
    let catalogOffset = data.count
    data.append(
      Data(
        ("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\n"
          + (omitsCatalogEndObject ? "" : "endobj\n")).utf8
      )
    )
    let pagesOffset = data.count
    data.append(Data("2 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    if duplicatesCatalog {
      data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".utf8))
    }
    let xrefOffset = data.count
    data.append(Data("xref\n0 3\n0000000000 65535 f \n".utf8))
    data.append(
      Data(String(format: "%010d 00000 n \n", catalogOffset + catalogCrossReferenceAdjustment).utf8)
    )
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 3 /Root 1 0 R >>\n".utf8))
    data.append(Data("startxref\n\(xrefOffset + startCrossReferenceAdjustment)\n%%EOF\n".utf8))
    return data
  }

  private func streamFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [Int]()
    offsets.append(data.count)
    data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Resources <<>> /Contents 4 0 R >>\nendobj\n".utf8))
    offsets.append(data.count)
    data.append(Data("4 0 obj\n<< /Length 3 >>\nstream\nabc endstream xyz\nendstream\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
    for offset in offsets {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  private func structureFixture() -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    let catalogOffset = data.count
    data.append(Data("1 0 obj\n<< /Pages 2 0 R >>\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("2 0 obj\n<< /Count 0 /Kids [] >>\nendobj\n".utf8))
    let xrefOffset = data.count
    data.append(Data("xref\n0 3\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", catalogOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 3 >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }
}

private struct TestRecoveryPass: PDFRecoveryPass {
  let descriptor = PDFRecoveryPassDescriptor(identifier: "test", stage: .sourceFraming)

  func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    _ = snapshot
    return .noMatch
  }
}

private struct BackwardsInvalidatingPass: PDFRecoveryPass {
  let descriptor = PDFRecoveryPassDescriptor(
    identifier: "backwards",
    stage: .documentStructure,
    invalidates: [.sourceFraming]
  )

  func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    _ = snapshot
    return .noMatch
  }
}

private struct OrderedRecoveryPass: PDFRecoveryPass {
  let descriptor: PDFRecoveryPassDescriptor

  init(identifier: String, priority: Int) {
    descriptor = PDFRecoveryPassDescriptor(
      identifier: identifier,
      stage: .sourceFraming,
      priority: priority
    )
  }

  func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    _ = snapshot
    return .noMatch
  }
}
