/// Bounded resource limits applied only while recovering a malformed PDF.
public struct PDFRecoveryLimits: Sendable, Hashable {
  /// Maximum source bytes inspected by recovery passes.
  public var maximumScanBytes: Int64
  /// Maximum indirect-object candidates retained during scanning.
  public var maximumCandidateObjects: Int
  /// Maximum revision candidates retained during scanning.
  public var maximumCandidateRevisions: Int
  /// Maximum distance searched while resynchronizing structural syntax.
  public var maximumResynchronizationBytes: Int
  /// Maximum distance searched for a missing stream boundary.
  public var maximumStreamBoundarySearchBytes: Int
  /// Maximum temporary recovery storage.
  public var maximumScratchBytes: Int
  /// Maximum applied recovery records.
  public var maximumAppliedRecords: Int
  /// Maximum proposals produced across all passes.
  public var maximumProposals: Int
  /// Maximum unresolved ambiguities retained for diagnostics.
  public var maximumAmbiguities: Int
  /// Maximum fixed-point generations executed by the coordinator.
  public var maximumPassGenerations: Int

  /// Creates recovery limits.
  public init(
    maximumScanBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
    maximumCandidateObjects: Int = 1_000_000,
    maximumCandidateRevisions: Int = 1_024,
    maximumResynchronizationBytes: Int = 16 * 1_024 * 1_024,
    maximumStreamBoundarySearchBytes: Int = 512 * 1_024 * 1_024,
    maximumScratchBytes: Int = 128 * 1_024 * 1_024,
    maximumAppliedRecords: Int = 65_536,
    maximumProposals: Int = 262_144,
    maximumAmbiguities: Int = 1_024,
    maximumPassGenerations: Int = 32
  ) {
    self.maximumScanBytes = maximumScanBytes
    self.maximumCandidateObjects = maximumCandidateObjects
    self.maximumCandidateRevisions = maximumCandidateRevisions
    self.maximumResynchronizationBytes = maximumResynchronizationBytes
    self.maximumStreamBoundarySearchBytes = maximumStreamBoundarySearchBytes
    self.maximumScratchBytes = maximumScratchBytes
    self.maximumAppliedRecords = maximumAppliedRecords
    self.maximumProposals = maximumProposals
    self.maximumAmbiguities = maximumAmbiguities
    self.maximumPassGenerations = maximumPassGenerations
  }

  package func validate() throws {
    guard maximumScanBytes >= 0,
      maximumCandidateObjects > 0,
      maximumCandidateRevisions > 0,
      maximumResynchronizationBytes > 0,
      maximumStreamBoundarySearchBytes > 0,
      maximumScratchBytes >= 256,
      maximumAppliedRecords > 0,
      maximumProposals > 0,
      maximumAmbiguities > 0,
      maximumPassGenerations > 0
    else {
      throw PDFParsingError.limitExceeded(
        .init(offset: 0, message: "PDF recovery limits must be positive and internally consistent.")
      )
    }
  }
}
