/// Options applied to one document rendering operation.
public struct PostScriptDocumentRenderOptions: Sendable, Hashable {
  public var dpi: Double
  public var cropMode: PostScriptDocumentCropMode
  public var background: PostScriptDocumentBackground
  public var pages: PostScriptDocumentPageSelection
  public var strict: Bool
  public var timeout: Duration?

  /// Creates rendering options.
  public init(
    dpi: Double = 144,
    cropMode: PostScriptDocumentCropMode = .automatic,
    background: PostScriptDocumentBackground = .white,
    pages: PostScriptDocumentPageSelection = .all,
    strict: Bool = true,
    timeout: Duration? = nil
  ) {
    self.dpi = dpi
    self.cropMode = cropMode
    self.background = background
    self.pages = pages
    self.strict = strict
    self.timeout = timeout
  }
}
