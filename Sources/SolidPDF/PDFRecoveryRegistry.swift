package struct PDFRecoveryRegistry: Sendable {
  package let passes: [any PDFRecoveryPass]

  package init(passes: [any PDFRecoveryPass]) throws {
    var identifiers = Set<String>()
    for pass in passes {
      guard identifiers.insert(pass.descriptor.identifier).inserted else {
        throw PDFParsingError.malformed(
          .init(offset: 0, message: "The recovery registry contains a duplicate pass identifier.")
        )
      }
      guard pass.descriptor.invalidates.allSatisfy({ $0.rawValue > pass.descriptor.stage.rawValue }) else {
        throw PDFParsingError.malformed(
          .init(offset: 0, message: "A recovery pass invalidates its own or an earlier stage.")
        )
      }
    }
    self.passes = passes.sorted { lhs, rhs in
      if lhs.descriptor.stage != rhs.descriptor.stage {
        return lhs.descriptor.stage.rawValue < rhs.descriptor.stage.rawValue
      }
      if lhs.descriptor.priority != rhs.descriptor.priority {
        return lhs.descriptor.priority < rhs.descriptor.priority
      }
      return lhs.descriptor.identifier < rhs.descriptor.identifier
    }
  }

  package static var builtIn: Self {
    get throws {
      try Self(passes: [
        PDFHeaderRecoveryPass(),
        PDFEndOfFileRecoveryPass(),
        PDFStartCrossReferenceRecoveryPass(),
        PDFCrossReferenceReconstructionPass(),
        PDFObjectBoundaryRecoveryPass(),
        PDFStreamBoundaryRecoveryPass(),
        PDFDocumentStructureRecoveryPass(),
      ])
    }
  }
}
