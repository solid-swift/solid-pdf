import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import SolidIO
import SolidPDF
import SolidPostScript
#if canImport(CoreText)
import SolidPostScriptCoreText
#endif
#if os(Linux)
import SolidPostScriptFreeType
#endif
import SolidPostScriptDocument
import SolidPostScriptPDF
import SolidPostScriptRaster
import SolidRaster
import SolidRasterPNG

@main
struct SolidPS: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "solid-ps",
    abstract: "Render PostScript and EPS documents.",
    subcommands: [Render.self]
  )
}

private struct Render: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Render selected pages as PNG images or a PDF document.")

  @Argument(help: "Input PS/EPS path, or - for standard input.")
  var input: String

  @Option(name: .long, help: "PDF/PNG file, PNG directory, or - for standard output.")
  var output: String

  @Option(name: .long, help: "Output format: auto, png, or pdf.")
  var format = OutputFormat.auto

  @Option(name: .long, help: "Output resolution in dots per inch.")
  var dpi = 144.0

  @Option(name: .long, help: "Pages: all or a comma-separated list of ordinals and ranges.")
  var pages = "all"

  @Option(name: .long, help: "Cropping: auto, media, or bounding-box.")
  var crop = "auto"

  @Option(name: .long, help: "white, transparent, #RRGGBB, or #RRGGBBAA.")
  var background = "white"

  @Flag(name: .long, help: "Record recoverable DSC problems as warnings.")
  var lenientDSC = false

  @Option(name: .long, parsing: .upToNextOption, help: "Directory readable by the PostScript program.")
  var allowRead: [String] = []

  @Option(name: .long, help: "Wall-clock timeout in seconds; zero disables it.")
  var timeout = 0.0

  @Flag(name: .long, help: "Replace generated output paths.")
  var force = false

  @Flag(name: .long, help: "Disable CoreText or FreeType host font discovery.")
  var noHostFonts = false

  @Flag(name: .long, help: "Suppress non-error diagnostics.")
  var quiet = false

  @Option(name: .long, help: "PDF compatibility version: 2.0 or 1.7.")
  var pdfVersion = PDFVersionOption.v2_0

  @Option(name: .long, help: "Resolution for exact PDF raster fallback.")
  var fallbackDPI = 300.0

  @Flag(name: .long, help: "Fail when an effect cannot be represented natively in PDF.")
  var noRasterFallback = false

  mutating func run() async throws {
    guard dpi.isFinite, dpi > 0, fallbackDPI.isFinite, fallbackDPI > 0,
      timeout.isFinite, timeout >= 0
    else {
      throw ValidationError("--dpi and --fallback-dpi must be positive and --timeout must be nonnegative")
    }
    let source: Data
    do { source = try readInput() }
    catch let error as ExitCode { throw error }
    catch { throw fail("cannot read input: \(error)", status: 66) }
    let assumedKind: PostScriptDocumentKind? = input == "-" ? nil : {
      let suffix = URL(fileURLWithPath: input).pathExtension.lowercased()
      return suffix == "eps" || suffix == "epsi" ? .encapsulatedPostScript : nil
    }()
    let document: PostScriptDocument
    do {
      let parsing = PostScriptDocumentParsingOptions(strict: !lenientDSC, assumedKind: assumedKind)
      document = try input == "-"
        ? PostScriptDocument.stagedStandardInput(source, options: parsing)
        : PostScriptDocument(data: source, options: parsing)
    } catch {
      throw fail("document error: \(error)", status: 65)
    }
    let pageSelection = try parsePages(pages)
    let parsedBackground = try parseBackground(background)
    let renderOptions = PostScriptDocumentRenderOptions(
      dpi: dpi,
      cropMode: try parseCrop(crop),
      background: parsedBackground,
      pages: pageSelection,
      strict: !lenientDSC,
      timeout: timeout == 0 ? nil : .seconds(timeout)
    )
    let environment = try makeEnvironment(standardInput: document.programData)
    if try resolvedFormat() == .pdf {
      try await renderPDF(
        document,
        documentOptions: renderOptions,
        environment: environment
      )
      return
    }
    let pngOptions = PNGEncodingOptions(
      colorFormat: parsedBackground == .transparent ? .rgba : .rgb,
      resolutionDPI: dpi,
      background: pngBackground(parsedBackground)
    )
    let encoder = try PNGEncoder(options: pngOptions)
    let staging = try makeStagingDirectory()
    defer { try? FileManager.default.removeItem(at: staging) }
    let sink = PNGStagingSink(directory: staging, selection: pageSelection, encoder: encoder)
    let rendered: GraphicsRenderResult<[StagedPNGPage]>
    do {
      if let timeout = renderOptions.timeout {
        rendered = try await withThrowingTaskGroup(of: GraphicsRenderResult<[StagedPNGPage]>.self) { group in
          group.addTask { try await document.renderRaster(to: sink, options: renderOptions, environment: environment) }
          group.addTask {
            try await Task.sleep(for: timeout)
            throw PostScriptDocumentError.timeout
          }
          guard let first = try await group.next() else { throw PostScriptDocumentError.timeout }
          group.cancelAll()
          return first
        }
      } else {
        rendered = try await document.renderRaster(to: sink, options: renderOptions, environment: environment)
      }
    } catch PostScriptDocumentError.timeout {
      throw fail("render timed out", status: 124)
    } catch is CancellationError {
      throw fail("render interrupted", status: 130)
    } catch {
      throw fail("render error: \(error)", status: 65)
    }
    do { try publish(rendered.output) }
    catch let error as ExitCode { throw error }
    catch { throw fail("output error: \(error)", status: 73) }
    if !quiet, output != "-" {
      FileHandle.standardError.write(Data("rendered \(rendered.output.count) page(s)\n".utf8))
    }
  }

  private func resolvedFormat() throws -> OutputFormat {
    guard format == .auto else { return format }
    guard output != "-" else {
      throw ValidationError("--format is required when writing to standard output")
    }
    switch URL(fileURLWithPath: output).pathExtension.lowercased() {
    case "pdf": return .pdf
    case "png": return .png
    default: return .png
    }
  }

  private func renderPDF(
    _ document: PostScriptDocument,
    documentOptions: PostScriptDocumentRenderOptions,
    environment: InterpreterEnvironment
  ) async throws {
    let options = PDFRenderOptions(
      version: pdfVersion.value,
      fallbackPolicy: noRasterFallback ? .vectorOnly : .exact,
      fallbackDPI: fallbackDPI
    )
    let rendered: GraphicsRenderResult<PDFEncodedDocument>
    do {
      rendered = try await document.renderPDF(
        options: options,
        documentOptions: documentOptions,
        environment: environment
      )
    } catch PostScriptDocumentError.timeout {
      throw fail("render timed out", status: 124)
    } catch is CancellationError {
      throw fail("render interrupted", status: 130)
    } catch {
      throw fail("render error: \(error)", status: 65)
    }
    do { try publishPDF(rendered.output.data) }
    catch let error as ExitCode { throw error }
    catch { throw fail("output error: \(error)", status: 73) }
    if !quiet {
      for diagnostic in rendered.output.diagnostics {
        FileHandle.standardError.write(Data("solid-ps: \(diagnostic.message)\n".utf8))
      }
      if output != "-" {
        FileHandle.standardError.write(Data("rendered \(rendered.output.pageCount) page(s)\n".utf8))
      }
    }
  }

  private func publishPDF(_ data: Data) throws {
    if output == "-" {
      FileHandle.standardOutput.write(data)
      return
    }
    let destination = URL(fileURLWithPath: output)
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path), !force { throw PDFError.outputExists }
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
    )
    do {
      try data.write(to: temporary)
      if manager.fileExists(atPath: destination.path) {
        try replacePublishedFile(at: destination, with: temporary)
      } else {
        try manager.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? manager.removeItem(at: temporary)
      throw error
    }
  }

  private func readInput() throws -> Data {
    if input == "-" {
      let data = FileHandle.standardInput.readDataToEndOfFile()
      guard data.count <= PostScriptDocumentLimits().maximumInputBytes else {
        throw PostScriptDocumentError.inputTooLarge
      }
      return data
    }
    do { return try Data(contentsOf: URL(fileURLWithPath: input), options: [.mappedIfSafe]) }
    catch { throw fail("cannot read input: \(error.localizedDescription)", status: 66) }
  }

  private func makeEnvironment(standardInput: Data) throws -> InterpreterEnvironment {
    let roots = allowRead.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let devices = if roots.isEmpty {
      FileDevices(devices: [])
    } else {
      FileDevices(devices: [try RootedReadOnlyFileDevice(roots: roots)])
    }
    let diagnostics = FileSink(fileHandle: .standardError)
    let host = InterpreterHostConfiguration(
      standardInput: DataSource(data: standardInput),
      standardOutput: diagnostics,
      standardError: diagnostics,
      interactiveExecutiveEnabled: false
    )
    if noHostFonts { return InterpreterEnvironment(hostConfiguration: host, fileDevices: devices) }
    #if canImport(CoreText)
    return .coreText(hostConfiguration: host, fileDevices: devices)
    #elseif os(Linux)
    return .freeTypeFontconfig(hostConfiguration: host, fileDevices: devices)
    #else
    return InterpreterEnvironment(hostConfiguration: host, fileDevices: devices)
    #endif
  }

  private func makeStagingDirectory() throws -> URL {
    let base: URL
    if output == "-" {
      base = FileManager.default.temporaryDirectory
    } else {
      let destination = URL(fileURLWithPath: output)
      base = destination.pathExtension.lowercased() == "png"
        ? destination.deletingLastPathComponent()
        : destination.deletingLastPathComponent()
    }
    let staging = base.appendingPathComponent(".solid-ps-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    return staging
  }

  private func publish(_ pages: [StagedPNGPage]) throws {
    if output == "-" {
      guard pages.count == 1 else { throw fail("standard output requires exactly one selected page", status: 64) }
      FileHandle.standardOutput.write(try Data(contentsOf: pages[0].url))
      return
    }
    let destination = URL(fileURLWithPath: output)
    if destination.pathExtension.lowercased() == "png" {
      guard pages.count == 1 else { throw fail("a .png destination requires exactly one selected page", status: 64) }
      if FileManager.default.fileExists(atPath: destination.path) {
        guard force else { throw PNGEncodingError.outputExists }
        try replacePublishedFile(at: destination, with: pages[0].url)
      } else {
        try FileManager.default.moveItem(at: pages[0].url, to: destination)
      }
      return
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let stem = input == "-" ? "stdin" : URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
    var pairs: [(temporary: URL, final: URL)] = []
    for page in pages {
      let name = String(format: "%@-%04d.png", stem, page.ordinal)
      let final = destination.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: final.path), !force { throw PNGEncodingError.outputExists }
      pairs.append((page.url, final))
    }
    for pair in pairs {
      if FileManager.default.fileExists(atPath: pair.final.path) {
        try replacePublishedFile(at: pair.final, with: pair.temporary)
      } else {
        try FileManager.default.moveItem(at: pair.temporary, to: pair.final)
      }
    }
  }
}

private func replacePublishedFile(at destination: URL, with temporary: URL) throws {
  #if canImport(Darwin) || canImport(Glibc)
  let result = temporary.withUnsafeFileSystemRepresentation { sourcePath in
    destination.withUnsafeFileSystemRepresentation { destinationPath in
      guard let sourcePath, let destinationPath else { return Int32(-1) }
      #if canImport(Darwin)
      return Darwin.rename(sourcePath, destinationPath)
      #else
      return Glibc.rename(sourcePath, destinationPath)
      #endif
    }
  }
  guard result == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
  #else
  _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
  #endif
}

private enum OutputFormat: String, ExpressibleByArgument {
  case auto
  case png
  case pdf
}

private enum PDFVersionOption: String, ExpressibleByArgument {
  case v2_0 = "2.0"
  case v1_7 = "1.7"

  var value: PDFVersion {
    switch self { case .v2_0: .v2_0; case .v1_7: .v1_7 }
  }
}

private func parsePages(_ value: String) throws -> PostScriptDocumentPageSelection {
  if value == "all" { return .all }
  var result = Set<Int>()
  for field in value.split(separator: ",") {
    let bounds = field.split(separator: "-", maxSplits: 1)
    guard let lower = Int(bounds[0]), lower > 0 else { throw ValidationError("invalid --pages value") }
    if bounds.count == 1 { result.insert(lower); continue }
    guard let upper = Int(bounds[1]), upper >= lower else { throw ValidationError("invalid --pages range") }
    result.formUnion(lower...upper)
  }
  guard !result.isEmpty else { throw ValidationError("empty --pages selection") }
  return .pages(result)
}

private func parseCrop(_ value: String) throws -> PostScriptDocumentCropMode {
  switch value {
  case "auto": .automatic
  case "media": .media
  case "bounding-box": .boundingBox
  default: throw ValidationError("invalid --crop value")
  }
}

private func parseBackground(_ value: String) throws -> PostScriptDocumentBackground {
  if value == "white" { return .white }
  if value == "transparent" { return .transparent }
  guard value.first == "#", value.count == 7 || value.count == 9,
    let number = UInt64(value.dropFirst(), radix: 16)
  else { throw ValidationError("invalid --background value") }
  if value.count == 7 {
    return .rgba(
      red: UInt8(truncatingIfNeeded: number >> 16),
      green: UInt8(truncatingIfNeeded: number >> 8),
      blue: UInt8(truncatingIfNeeded: number),
      alpha: 255
    )
  }
  return .rgba(
    red: UInt8(truncatingIfNeeded: number >> 24),
    green: UInt8(truncatingIfNeeded: number >> 16),
    blue: UInt8(truncatingIfNeeded: number >> 8),
    alpha: UInt8(truncatingIfNeeded: number)
  )
}

private func pngBackground(_ value: PostScriptDocumentBackground) -> PNGBackground {
  switch value {
  case .white, .transparent: .white
  case .rgba(let red, let green, let blue, _): .init(red: red, green: green, blue: blue)
  }
}

private func fail(_ message: String, status: Int32) -> ExitCode {
  FileHandle.standardError.write(Data("solid-ps: \(message)\n".utf8))
  return ExitCode(status)
}

private struct StagedPNGPage: Sendable {
  let ordinal: Int
  let url: URL
}

private struct PNGStagingSink: RasterPageSink, Sendable {
  final class Session: RasterPageSinkSession {
    private let directory: URL
    private let selection: PostScriptDocumentPageSelection
    private let encoder: PNGEncoder
    private var transmitted = 0
    private var pages: [StagedPNGPage] = []

    init(directory: URL, selection: PostScriptDocumentPageSelection, encoder: PNGEncoder) {
      self.directory = directory
      self.selection = selection
      self.encoder = encoder
    }

    func consume(_ page: RasterRenderedPage) throws {
      transmitted += 1
      guard selection.contains(transmitted) else { return }
      let url = directory.appendingPathComponent(String(format: "page-%08d.png", transmitted))
      try encoder.encode(page.image, to: url)
      pages.append(StagedPNGPage(ordinal: transmitted, url: url))
    }

    func finish() throws -> sending [StagedPNGPage] {
      if case .pages(let requested) = selection,
        requested.contains(where: { $0 > transmitted })
      {
        throw PostScriptDocumentError.invalidPageSelection
      }
      guard !pages.isEmpty else { throw PostScriptDocumentError.noPages }
      return pages
    }

    func abort() {
      pages.removeAll()
    }
  }

  let directory: URL
  let selection: PostScriptDocumentPageSelection
  let encoder: PNGEncoder

  func makeSession() -> sending Session {
    Session(directory: directory, selection: selection, encoder: encoder)
  }
}
