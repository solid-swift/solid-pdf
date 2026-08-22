import Foundation
import SolidColor
import SolidPDF
import SolidPostScript

final class PDFGraphicsInstructionHandler<Source: PDFInputSource>: PDFContentInstructionHandler {
  typealias Emit = (GraphicsEvent) throws -> Void

  let resources: PDFGraphicsResourceResolver<Source>
  let output: PDFGraphicsEventOutput
  let limits: PDFGraphicsLimits
  var state: PDFGraphicsState
  private var stack: [PDFGraphicsState] = []
  private var currentPoint: GraphicsPoint?
  private var subpathStart: GraphicsPoint?
  private var diagnosticsStorage: [PDFGraphicsDiagnostic] = []
  var textMatrix: GraphicsMatrix?
  var textLineMatrix: GraphicsMatrix?
  var textClipElements: [GraphicsPath.Element] = []
  var interpretedGlyphCount = 0
  let type3Capture: PDFType3GlyphCapture?
  let type3Depth: Int
  private var markedContent: [GraphicsMarkedContentScope] = []

  var diagnostics: [PDFGraphicsDiagnostic] { diagnosticsStorage + resources.diagnostics }
  var currentSnapshot: GraphicsStateSnapshot { state.snapshot(stroking: false) }

  convenience init(
    device: GraphicsDeviceSnapshot,
    resources: PDFGraphicsResourceResolver<Source>,
    limits: PDFGraphicsLimits,
    emit: @escaping Emit
  ) {
    self.init(
      device: device,
      resources: resources,
      limits: limits,
      output: PDFGraphicsClosureOutput(emit: emit)
    )
  }

  init(
    device: GraphicsDeviceSnapshot,
    resources: PDFGraphicsResourceResolver<Source>,
    limits: PDFGraphicsLimits,
    output: PDFGraphicsEventOutput,
    initialState: PDFGraphicsState? = nil,
    type3Capture: PDFType3GlyphCapture? = nil,
    type3Depth: Int = 0
  ) {
    state = initialState ?? PDFGraphicsState(device: device)
    self.resources = resources
    self.limits = limits
    self.output = output
    self.type3Capture = type3Capture
    self.type3Depth = type3Depth
  }

  func emit(_ event: GraphicsEvent) throws { try output.process(decorated(event)) }

  func decorated(_ event: GraphicsEvent) -> GraphicsEvent {
    let path = markedContent + event.markedContentPath
    let hidden = path.flatMap { scope -> [GraphicsResourceIdentifier] in
      if case .hidden(let identifiers) = scope.visibility { return identifiers }
      return []
    }
    return GraphicsEvent(
      operation: event.operation,
      before: event.before,
      after: event.after,
      origin: event.origin,
      markedContentPath: path,
      visibility: hidden.isEmpty ? event.visibility : .hidden(Array(Set(hidden)).sorted { $0.rawValue < $1.rawValue })
    )
  }

  var currentTextReplacement: GraphicsTextReplacement? {
    markedContent.reversed().compactMap(\.properties.replacement).first
  }

  func recordDiagnostic(_ diagnostic: PDFGraphicsDiagnostic) {
    diagnosticsStorage.append(diagnostic)
  }

  func execute(_ instruction: PDFContentInstruction) async throws {
    do {
      try validateType3Instruction(instruction)
      switch instruction.name {
      case "q":
        try operands(instruction, count: 0)
        guard stack.count < limits.maximumGraphicsStateDepth else {
          throw PDFGraphicsError.limitExceeded("PDF graphics-state stack limit exceeded.", location: instruction.location)
        }
        stack.append(state)
        try emitState(.save, at: instruction.location) { _ in }
      case "Q":
        try operands(instruction, count: 0)
        guard let restored = stack.popLast() else { throw malformed("Graphics-state stack underflow.", instruction) }
        let before = state.snapshot(stroking: false)
        state = restored
        try emit(GraphicsEvent(
          operation: .state(.restore),
          before: before,
          after: state.snapshot(stroking: false),
          origin: origin(instruction.location)
        ))
      case "cm":
        let values = try numbers(instruction, count: 6)
        let matrix = GraphicsMatrix(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
        try emitState(.concatenate(matrix), at: instruction.location) {
          $0.matrix = matrix.concatenated(with: $0.matrix)
        }
      case "w":
        let value = try numbers(instruction, count: 1)[0]
        guard value >= 0 else { throw malformed("Negative line width.", instruction) }
        try emitState(.setLineWidth(value), at: instruction.location) { $0.lineWidth = value }
      case "J":
        let value = try integer(instruction, count: 1)
        guard let cap = GraphicsLineCap(rawValue: Int32(value)) else { throw malformed("Invalid line cap.", instruction) }
        try emitState(.setLineCap(cap), at: instruction.location) { $0.lineCap = cap }
      case "j":
        let value = try integer(instruction, count: 1)
        guard let join = GraphicsLineJoin(rawValue: Int32(value)) else { throw malformed("Invalid line join.", instruction) }
        try emitState(.setLineJoin(join), at: instruction.location) { $0.lineJoin = join }
      case "M":
        let value = try numbers(instruction, count: 1)[0]
        guard value >= 1 else { throw malformed("Invalid miter limit.", instruction) }
        try emitState(.setMiterLimit(value), at: instruction.location) { $0.miterLimit = value }
      case "d":
        try operands(instruction, count: 2)
        let pattern = try PDFObjectAccess.numbers(instruction.operands[0])
        let phase = try PDFObjectAccess.number(instruction.operands[1])
        guard pattern.allSatisfy({ $0 >= 0 }), pattern.reduce(0, +) > 0 || pattern.isEmpty else {
          throw malformed("Invalid dash pattern.", instruction)
        }
        let dash = GraphicsDash(pattern: pattern, phase: phase)
        try emitState(.setDash(dash), at: instruction.location) { $0.dash = dash }
      case "ri":
        try operands(instruction, count: 1)
        let name = try PDFObjectAccess.name(instruction.operands[0]).pdfGraphicsString
        guard let intent = Self.renderingIntent(name) else { throw malformed("Invalid rendering intent.", instruction) }
        let before = state.snapshot(stroking: false)
        state.renderingIntent = intent
        try emit(GraphicsEvent(
          operation: .state(.setColorRendering),
          before: before,
          after: state.snapshot(stroking: false),
          origin: origin(instruction.location)
        ))
      case "i":
        let value = try numbers(instruction, count: 1)[0]
        guard value >= 0, value <= 100 else { throw malformed("Invalid flatness.", instruction) }
        try emitState(.setFlatness(value), at: instruction.location) { $0.flatness = value }
      case "m": try move(instruction)
      case "l": try line(instruction)
      case "c": try curve(instruction)
      case "v": try curveV(instruction)
      case "y": try curveY(instruction)
      case "h": try close(instruction)
      case "re": try rectangle(instruction)
      case "W": try pendingClip(.winding, instruction)
      case "W*": try pendingClip(.evenOdd, instruction)
      case "S": try paint(stroke: true, fill: nil, close: false, instruction)
      case "s": try paint(stroke: true, fill: nil, close: true, instruction)
      case "f", "F": try paint(stroke: false, fill: .winding, close: false, instruction)
      case "f*": try paint(stroke: false, fill: .evenOdd, close: false, instruction)
      case "B": try paint(stroke: true, fill: .winding, close: false, instruction)
      case "B*": try paint(stroke: true, fill: .evenOdd, close: false, instruction)
      case "b": try paint(stroke: true, fill: .winding, close: true, instruction)
      case "b*": try paint(stroke: true, fill: .evenOdd, close: true, instruction)
      case "n": try endPath(instruction)
      case "G": try setDeviceGray(instruction, stroking: true)
      case "g": try setDeviceGray(instruction, stroking: false)
      case "RG": try setDeviceRGB(instruction, stroking: true)
      case "rg": try setDeviceRGB(instruction, stroking: false)
      case "K": try setDeviceCMYK(instruction, stroking: true)
      case "k": try setDeviceCMYK(instruction, stroking: false)
      case "CS": try await setColorSpace(instruction, stroking: true)
      case "cs": try await setColorSpace(instruction, stroking: false)
      case "SC", "SCN": try await setColor(instruction, stroking: true)
      case "sc", "scn": try await setColor(instruction, stroking: false)
      case "gs": try await applyExtendedState(instruction)
      case "BT": try beginText(instruction)
      case "ET": try endText(instruction)
      case "Tc": try setCharacterSpacing(instruction)
      case "Tw": try setWordSpacing(instruction)
      case "Tz": try setHorizontalScaling(instruction)
      case "TL": try setTextLeading(instruction)
      case "Tf": try await setTextFont(instruction)
      case "Tr": try setTextRenderingMode(instruction)
      case "Ts": try setTextRise(instruction)
      case "Td": try moveText(instruction, setsLeading: false)
      case "TD": try moveText(instruction, setsLeading: true)
      case "Tm": try setTextMatrix(instruction)
      case "T*": try nextTextLine(instruction)
      case "Tj": try await showText(instruction)
      case "TJ": try await showTextArray(instruction)
      case "'": try await showNextLine(instruction, setsSpacing: false)
      case "\"": try await showNextLine(instruction, setsSpacing: true)
      case "BMC", "BDC", "EMC", "MP", "DP":
        try await interpretMarkedContent(instruction)
      case "Do": try await paintXObject(instruction)
      case "sh": try await paintShading(instruction)
      case "BI": throw PDFGraphicsError.unsupported(.operatorName("BI"), location: instruction.location)
      case "d0": try setType3Width(instruction)
      case "d1": try setType3CacheDevice(instruction)
      case "ID", "EI": throw malformed("Inline-image delimiter outside an inline image.", instruction)
      default: throw malformed("Unimplemented known operator.", instruction)
      }
    } catch let error as PDFGraphicsError {
      throw error
    } catch {
      throw malformed("Invalid PDF operator operands.", instruction)
    }
  }

  func finish(at location: PDFContentLocation?) async throws {
    if let type3Capture, type3Capture.metrics == nil {
      throw PDFGraphicsError.malformedContent(
        message: "Type 3 CharProc did not begin with d0 or d1.",
        operatorName: nil,
        location: location ?? type3Capture.location
      )
    }
    guard stack.isEmpty else {
      throw PDFGraphicsError.malformedContent(
        message: "PDF graphics-state stack is not balanced.",
        operatorName: "q",
        location: location!
      )
    }
    guard markedContent.isEmpty else {
      throw PDFGraphicsError.malformedContent(
        message: "PDF marked-content stack is not balanced.",
        operatorName: "BMC",
        location: location!
      )
    }
  }

  private func validateType3Instruction(_ instruction: PDFContentInstruction) throws {
    guard let capture = type3Capture else { return }
    if capture.metrics == nil, instruction.name != "d0", instruction.name != "d1" {
      throw malformed("Type 3 CharProc artwork precedes d0 or d1.", instruction)
    }
    guard capture.mode == .uncolored else { return }
    let colorDependent = [
      "G", "g", "RG", "rg", "K", "k", "CS", "cs", "SC", "SCN", "sc", "scn", "sh",
    ]
    if colorDependent.contains(instruction.name) {
      throw malformed("A d1 Type 3 CharProc contains color-dependent artwork.", instruction)
    }
  }

  private func setType3Width(_ instruction: PDFContentInstruction) throws {
    guard let capture = type3Capture else {
      throw PDFGraphicsError.unsupported(.operatorName("d0"), location: instruction.location)
    }
    let values = try numbers(instruction, count: 2)
    try capture.establish(
      mode: .colorized,
      metrics: GraphicsGlyphMetrics(horizontalAdvance: .init(x: values[0], y: values[1])),
      instruction: instruction
    )
  }

  private func setType3CacheDevice(_ instruction: PDFContentInstruction) throws {
    guard let capture = type3Capture else {
      throw PDFGraphicsError.unsupported(.operatorName("d1"), location: instruction.location)
    }
    let values = try numbers(instruction, count: 6)
    let bounds = GraphicsRect(
      x: min(values[2], values[4]),
      y: min(values[3], values[5]),
      width: abs(values[4] - values[2]),
      height: abs(values[5] - values[3])
    )
    try capture.establish(
      mode: .uncolored,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: .init(x: values[0], y: values[1]),
        bounds: bounds
      ),
      instruction: instruction
    )
    // An uncolored Type 3 glyph paints exclusively with the caller's nonstroking color.
    state.stroking = state.nonstroking
  }

  private func move(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    let values = try numbers(instruction, count: 2)
    let point = state.matrix.transform(GraphicsPoint(x: values[0], y: values[1]))
    state.pathElements.append(.move(to: point))
    currentPoint = point
    subpathStart = point
    try emitPath(.move(to: point), before: before, instruction)
  }

  private func line(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    guard currentPoint != nil else { throw malformed("Line without a current point.", instruction) }
    let values = try numbers(instruction, count: 2)
    let point = state.matrix.transform(GraphicsPoint(x: values[0], y: values[1]))
    state.pathElements.append(.line(to: point))
    currentPoint = point
    try emitPath(.line(to: point), before: before, instruction)
  }

  private func curve(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    guard currentPoint != nil else { throw malformed("Curve without a current point.", instruction) }
    let values = try numbers(instruction, count: 6)
    try appendCurve(
      state.matrix.transform(GraphicsPoint(x: values[0], y: values[1])),
      state.matrix.transform(GraphicsPoint(x: values[2], y: values[3])),
      state.matrix.transform(GraphicsPoint(x: values[4], y: values[5])),
      before: before,
      instruction: instruction
    )
  }

  private func curveV(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    guard let currentPoint else { throw malformed("Curve without a current point.", instruction) }
    let values = try numbers(instruction, count: 4)
    try appendCurve(
      currentPoint,
      state.matrix.transform(GraphicsPoint(x: values[0], y: values[1])),
      state.matrix.transform(GraphicsPoint(x: values[2], y: values[3])),
      before: before,
      instruction: instruction
    )
  }

  private func curveY(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    guard currentPoint != nil else { throw malformed("Curve without a current point.", instruction) }
    let values = try numbers(instruction, count: 4)
    let end = state.matrix.transform(GraphicsPoint(x: values[2], y: values[3]))
    try appendCurve(
      state.matrix.transform(GraphicsPoint(x: values[0], y: values[1])),
      end,
      end,
      before: before,
      instruction: instruction
    )
  }

  private func appendCurve(
    _ control1: GraphicsPoint,
    _ control2: GraphicsPoint,
    _ end: GraphicsPoint,
    before: GraphicsStateSnapshot,
    instruction: PDFContentInstruction
  ) throws {
    let element = GraphicsPath.Element.curve(control1: control1, control2: control2, end: end)
    state.pathElements.append(element)
    currentPoint = end
    try emitPath(.curve(control1: control1, control2: control2, end: end), before: before, instruction)
  }

  private func close(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    try operands(instruction, count: 0)
    guard currentPoint != nil else { throw malformed("closepath without a current point.", instruction) }
    if !state.pathElements.isEmpty, case .close = state.pathElements.last { return }
    state.pathElements.append(.close)
    currentPoint = subpathStart
    try emitPath(.close, before: before, instruction)
  }

  private func rectangle(_ instruction: PDFContentInstruction) throws {
    let before = state.snapshot(stroking: false)
    let values = try numbers(instruction, count: 4)
    let points = [
      GraphicsPoint(x: values[0], y: values[1]),
      GraphicsPoint(x: values[0] + values[2], y: values[1]),
      GraphicsPoint(x: values[0] + values[2], y: values[1] + values[3]),
      GraphicsPoint(x: values[0], y: values[1] + values[3]),
    ].map(state.matrix.transform)
    state.pathElements.append(contentsOf: [
      .move(to: points[0]), .line(to: points[1]), .line(to: points[2]), .line(to: points[3]), .close,
    ])
    currentPoint = points[0]
    subpathStart = points[0]
    try emitPath(.move(to: points[0]), before: before, instruction)
  }

  private func pendingClip(_ rule: GraphicsFillRule, _ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 0)
    state.pendingClip = rule
  }

  private func paint(
    stroke: Bool,
    fill: GraphicsFillRule?,
    close shouldClose: Bool,
    _ instruction: PDFContentInstruction
  ) throws {
    try operands(instruction, count: 0)
    if shouldClose { try close(PDFContentInstruction(operands: [], name: "h", location: instruction.location)) }
    let path = GraphicsPath(elements: state.pathElements)
    if let fill {
      let snapshot = state.snapshot(stroking: false, path: path)
      try emit(GraphicsEvent(
        operation: .paint(.fill(fill)),
        before: snapshot,
        after: snapshot,
        origin: origin(instruction.location)
      ))
    }
    if stroke {
      let snapshot = state.snapshot(stroking: true, path: path)
      try emit(GraphicsEvent(
        operation: .paint(.stroke),
        before: snapshot,
        after: snapshot,
        origin: origin(instruction.location)
      ))
    }
    try clearPath(applyingClipFrom: path, instruction)
  }

  private func endPath(_ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 0)
    try clearPath(applyingClipFrom: GraphicsPath(elements: state.pathElements), instruction)
  }

  private func clearPath(
    applyingClipFrom path: GraphicsPath,
    _ instruction: PDFContentInstruction
  ) throws {
    if let rule = state.pendingClip {
      state.clip = GraphicsClip(
        imageableBounds: state.clip.imageableBounds,
        constraints: state.clip.constraints + [GraphicsClipConstraint(path: path, rule: rule)]
      )
    }
    let before = state.snapshot(stroking: false, path: path)
    state.pathElements.removeAll(keepingCapacity: true)
    state.pendingClip = nil
    currentPoint = nil
    subpathStart = nil
    try emit(GraphicsEvent(
      operation: .path(.new),
      before: before,
      after: state.snapshot(stroking: false),
      origin: origin(instruction.location)
    ))
  }

  private func setDeviceGray(_ instruction: PDFContentInstruction, stroking: Bool) throws {
    let values = try numbers(instruction, count: 1)
    try setColorState(
      PDFGraphicsState.ColorState(space: .deviceGray, components: values, paint: .deviceGray(values[0])),
      stroking: stroking,
      operation: .setGray(values[0]),
      location: instruction.location
    )
  }

  private func setDeviceRGB(_ instruction: PDFContentInstruction, stroking: Bool) throws {
    let values = try numbers(instruction, count: 3)
    try setColorState(
      PDFGraphicsState.ColorState(
        space: .deviceRGB,
        components: values,
        paint: .deviceRGB(red: values[0], green: values[1], blue: values[2])
      ),
      stroking: stroking,
      operation: .setRGB(red: values[0], green: values[1], blue: values[2]),
      location: instruction.location
    )
  }

  private func setDeviceCMYK(_ instruction: PDFContentInstruction, stroking: Bool) throws {
    let values = try numbers(instruction, count: 4)
    try setColorState(
      PDFGraphicsState.ColorState(
        space: .deviceCMYK,
        components: values,
        paint: .deviceCMYK(cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
      ),
      stroking: stroking,
      operation: .setCMYK(cyan: values[0], magenta: values[1], yellow: values[2], black: values[3]),
      location: instruction.location
    )
  }

  private func setColorSpace(_ instruction: PDFContentInstruction, stroking: Bool) async throws {
    try operands(instruction, count: 1)
    let name = try PDFObjectAccess.name(instruction.operands[0])
    let space = try await resources.colorSpace(named: name)
    let color = PDFGraphicsState.ColorState(
      space: space.description,
      realization: space.realization,
      components: space.initialComponents,
      paint: try space.makePaint(space.initialComponents),
      makePaint: space.makePaint,
      underlyingMakePaint: space.underlyingMakePaint
    )
    try setColorState(
      color,
      stroking: stroking,
      operation: .setColorSpace(space.description),
      location: instruction.location
    )
  }

  private func setColor(_ instruction: PDFContentInstruction, stroking: Bool) async throws {
    let current = stroking ? state.stroking : state.nonstroking
    guard case .pattern = current.space else {
      let values = try instruction.operands.map(PDFObjectAccess.number)
      guard values.count == current.space.componentCount else { throw malformed("Wrong color component count.", instruction) }
      let paint = try current.makePaint?(values) ?? Self.devicePaint(space: current.space, values: values)
      try setColorState(
        PDFGraphicsState.ColorState(
          space: current.space,
          realization: current.realization,
          components: values,
          paint: paint,
          makePaint: current.makePaint
        ),
        stroking: stroking,
        operation: .setColor(Self.colorValue(paint)),
        location: instruction.location
      )
      return
    }
    guard let last = instruction.operands.last else { throw malformed("Pattern name is missing.", instruction) }
    let name = try PDFObjectAccess.name(last)
    let values = try instruction.operands.dropLast().map(PDFObjectAccess.number)
    let underlying: GraphicsPaint?
    if let makePaint = current.underlyingMakePaint {
      guard values.count == current.components.count else { throw malformed("Wrong pattern component count.", instruction) }
      underlying = try makePaint(values)
    } else {
      guard values.isEmpty else { throw malformed("Colored pattern has color components.", instruction) }
      underlying = nil
    }
    let pattern = try await compilePattern(named: name, underlying: underlying, instruction: instruction)
    let paint = GraphicsPaint.pattern(pattern)
    try setColorState(
      PDFGraphicsState.ColorState(
        space: current.space,
        realization: current.realization,
        components: values,
        paint: paint,
        makePaint: current.makePaint,
        underlyingMakePaint: current.underlyingMakePaint
      ),
      stroking: stroking,
      operation: .setColor(Self.colorValue(paint)),
      location: instruction.location
    )
  }

  private func applyExtendedState(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 1)
    let name = try PDFObjectAccess.name(instruction.operands[0])
    guard let resource = try await resources.resource(category: "ExtGState", name: name),
      case .value(.dictionary(let dictionary)) = resource.value
    else { throw malformed("Missing ExtGState resource.", instruction) }
    if let blend = dictionary["BM"] {
      let blendName: PDFName
      switch blend {
      case .name(let name): blendName = name
      case .array(let values): blendName = try PDFObjectAccess.name(values.first ?? .null)
      default: throw malformed("Invalid blend mode.", instruction)
      }
      guard blendName.pdfGraphicsString == "Normal" || blendName.pdfGraphicsString == "Compatible" else {
        throw PDFGraphicsError.unsupported(.transparency(blendName), location: instruction.location)
      }
    }
    for key in [PDFName("ca"), PDFName("CA")] {
      if let alpha = dictionary[key], try PDFObjectAccess.number(alpha) != 1 {
        throw PDFGraphicsError.unsupported(.transparency(key), location: instruction.location)
      }
    }
    if let softMask = dictionary["SMask"], softMask != .name("None") {
      throw PDFGraphicsError.unsupported(.transparency("SMask"), location: instruction.location)
    }
    if let alphaSource = dictionary["AIS"], alphaSource != .boolean(false) {
      throw PDFGraphicsError.unsupported(.transparency("AIS"), location: instruction.location)
    }
    if let mode = dictionary["OPM"], try PDFObjectAccess.integer(mode) == 1 {
      throw PDFGraphicsError.unsupported(.overprintModeOne, location: instruction.location)
    }
    if let value = dictionary["OP"] {
      guard case .boolean(let enabled) = value else { throw malformed("Invalid stroking overprint.", instruction) }
      state.strokingOverprint = enabled
    }
    if let value = dictionary["op"] {
      guard case .boolean(let enabled) = value else { throw malformed("Invalid nonstroking overprint.", instruction) }
      state.nonstrokingOverprint = enabled
    }
    if let value = dictionary["LW"] { state.lineWidth = try PDFObjectAccess.number(value) }
    if let value = dictionary["LC"], let cap = GraphicsLineCap(rawValue: Int32(try PDFObjectAccess.integer(value))) {
      state.lineCap = cap
    }
    if let value = dictionary["LJ"], let join = GraphicsLineJoin(rawValue: Int32(try PDFObjectAccess.integer(value))) {
      state.lineJoin = join
    }
    if let value = dictionary["ML"] { state.miterLimit = try PDFObjectAccess.number(value) }
    if let value = dictionary["D"] {
      let values = try PDFObjectAccess.array(value)
      guard values.count == 2 else { throw malformed("Invalid ExtGState dash pattern.", instruction) }
      state.dash = GraphicsDash(
        pattern: try PDFObjectAccess.numbers(values[0]),
        phase: try PDFObjectAccess.number(values[1])
      )
    }
    if let value = dictionary["RI"] {
      guard let intent = Self.renderingIntent(try PDFObjectAccess.name(value).pdfGraphicsString) else {
        throw malformed("Invalid rendering intent.", instruction)
      }
      state.renderingIntent = intent
    }
    if let value = dictionary["FL"] { state.flatness = try PDFObjectAccess.number(value) }
    if let value = dictionary["SA"] {
      guard case .boolean(let enabled) = value else { throw malformed("Invalid stroke adjustment.", instruction) }
      state.strokeAdjustment = enabled
    }
    if let value = dictionary["SM"] { state.smoothness = try PDFObjectAccess.number(value) }
    if let value = dictionary["TR2"] ?? dictionary["TR"] {
      let functions: GraphicsTransferFunctions
      if case .array(let values) = value {
        guard values.count == 4 else { throw malformed("Invalid transfer function array.", instruction) }
        functions = try await GraphicsTransferFunctions(
          red: resources.componentFunction(values[0]),
          green: resources.componentFunction(values[1]),
          blue: resources.componentFunction(values[2]),
          gray: resources.componentFunction(values[3])
        )
      } else {
        let function = try await resources.componentFunction(value)
        functions = GraphicsTransferFunctions(red: function, green: function, blue: function, gray: function)
      }
      replaceDeviceRendering(transferFunctions: functions)
    }
    if let value = dictionary["BG2"] ?? dictionary["BG"] {
      if case .name(let name) = value, name.pdfGraphicsString == "Default" {
        replaceDeviceRendering(blackGeneration: .zero)
      } else {
        replaceDeviceRendering(blackGeneration: try await resources.componentFunction(value))
      }
    }
    if let value = dictionary["UCR2"] ?? dictionary["UCR"] {
      if case .name(let name) = value, name.pdfGraphicsString == "Default" {
        replaceDeviceRendering(undercolorRemoval: .zero)
      } else {
        replaceDeviceRendering(undercolorRemoval: try await resources.componentFunction(value))
      }
    }
    if let value = dictionary["HT"] {
      if case .name(let name) = value, name.pdfGraphicsString == "Default" {
        replaceDeviceRendering(halftone: state.device.descriptor.deviceRendering.defaultState.halftone)
      } else {
        do {
          replaceDeviceRendering(halftone: try await resources.halftone(
            value,
            device: state.device.descriptor,
            maximumBytes: limits.maximumScratchBytes
          ))
        } catch PDFGraphicsError.limitExceeded(let message, location: nil) {
          throw PDFGraphicsError.limitExceeded(message, location: instruction.location)
        }
      }
    }
    if let value = dictionary["HTP"] {
      let phase = try PDFObjectAccess.numbers(value)
      guard phase.count == 2 else { throw malformed("Invalid halftone phase.", instruction) }
      replaceDeviceRendering(halftonePhase: GraphicsPoint(x: phase[0], y: phase[1]))
    }
    let snapshot = state.snapshot(stroking: false)
    try emit(GraphicsEvent(
      operation: .state(.setColorRendering),
      before: snapshot,
      after: snapshot,
      origin: origin(instruction.location)
    ))
  }

  private func interpretMarkedContent(_ instruction: PDFContentInstruction) async throws {
    switch instruction.name {
    case "BMC":
      let scope = try await markedContentScope(instruction, hasProperties: false)
      guard markedContent.count < limits.maximumMarkedContentDepth else {
        throw PDFGraphicsError.limitExceeded("PDF marked-content depth exceeded.", location: instruction.location)
      }
      markedContent.append(scope)
      try emit(markedContentEvent(.begin(scope), instruction: instruction))
    case "BDC":
      let scope = try await markedContentScope(instruction, hasProperties: true)
      guard markedContent.count < limits.maximumMarkedContentDepth else {
        throw PDFGraphicsError.limitExceeded("PDF marked-content depth exceeded.", location: instruction.location)
      }
      markedContent.append(scope)
      try emit(markedContentEvent(.begin(scope), instruction: instruction))
    case "EMC":
      guard let scope = markedContent.last else { throw malformed("Marked-content stack underflow.", instruction) }
      try emit(markedContentEvent(.end(scope), instruction: instruction))
      markedContent.removeLast()
    case "MP", "DP":
      let scope = try await markedContentScope(instruction, hasProperties: instruction.name == "DP")
      try emit(markedContentEvent(.point(scope), instruction: instruction))
    default:
      preconditionFailure("Unexpected marked-content operator.")
    }
  }

  private func markedContentScope(
    _ instruction: PDFContentInstruction,
    hasProperties: Bool
  ) async throws -> GraphicsMarkedContentScope {
    let tag = try PDFObjectAccess.name(instruction.operands[0])
    var dictionary: [PDFName: PDFObject] = [:]
    var visibilityObject: PDFObject?
    var resourceIdentifier = GraphicsResourceIdentifier(
      rawValue: "pdf:marked:r\(instruction.location.revision.ordinal):p\(instruction.location.pageIndex):\(instruction.location.decodedOffset)"
    )
    if hasProperties {
      switch instruction.operands[1] {
      case .dictionary(let value):
        dictionary = value
        visibilityObject = instruction.operands[1]
      case .name(let name):
        guard let property = try await resources.markedContentProperty(named: name) else {
          throw malformed("Marked-content property resource is missing.", instruction)
        }
        dictionary = property.value
        visibilityObject = property.source
        resourceIdentifier = property.identifier
      default:
        throw malformed("Marked-content properties are invalid.", instruction)
      }
    }
    guard dictionary.count <= limits.maximumMarkedContentProperties else {
      throw PDFGraphicsError.limitExceeded("PDF marked-content property limit exceeded.", location: instruction.location)
    }
    let ownerReference = instruction.location.segments.first?.streamReference ?? instruction.location.pageReference
    let owner = GraphicsResourceIdentifier(
      rawValue: "pdf:r\(instruction.location.revision.ordinal):o\(ownerReference.objectNumber):\(ownerReference.generationNumber)"
    )
    let catalog = try await resources.document.catalog(in: resources.revision)
    let properties = try markedContentProperties(
      dictionary,
      tag: tag,
      owner: owner,
      resource: resourceIdentifier,
      allowsUTF8: catalog.effectiveVersion == .v2_0
    )
    let visibility: GraphicsContentVisibility
    if tag == PDFName("OC"), let visibilityObject {
      let result = try await resources.document.optionalContentVisibility(
        of: visibilityObject,
        selection: resources.optionalContentSelection,
        context: resources.optionalContentContext,
        in: resources.revision
      )
      visibility = result.isVisible ? .visible : .hidden(result.controllingGroups.map {
        GraphicsResourceIdentifier(
          rawValue: "pdf:r\(resources.revision.ordinal):o\($0.reference.objectNumber):\($0.reference.generationNumber)"
        )
      })
    } else {
      visibility = .visible
    }
    return GraphicsMarkedContentScope(
      resourceIdentifier: resourceIdentifier,
      tag: tag.bytes,
      properties: properties,
      visibility: visibility
    )
  }

  private func markedContentProperties(
    _ dictionary: [PDFName: PDFObject],
    tag: PDFName,
    owner: GraphicsResourceIdentifier,
    resource: GraphicsResourceIdentifier,
    allowsUTF8: Bool
  ) throws -> GraphicsMarkedContentProperties {
    let identifier: GraphicsMarkedContentIdentifier?
    if let object = dictionary["MCID"] {
      let value = try PDFObjectAccess.integer(object)
      guard value >= 0 else { throw PDFObjectAccess.TypeMismatch.number }
      identifier = .init(owner: owner, value: value)
    } else { identifier = nil }
    let replacement = try textProperty(dictionary["ActualText"], allowsUTF8: allowsUTF8).map {
      GraphicsTextReplacement(text: $0, provenance: .markedContent)
    }
    let artifact: GraphicsArtifactDescription?
    if tag == PDFName("Artifact") {
      artifact = GraphicsArtifactDescription(
        type: nameBytes(dictionary["Type"]),
        subtype: nameBytes(dictionary["Subtype"]),
        bounds: try rectangle(dictionary["BBox"]),
        attachments: try names(dictionary["Attached"])
      )
    } else { artifact = nil }
    return GraphicsMarkedContentProperties(
      identifier: identifier,
      language: try textProperty(dictionary["Lang"], allowsUTF8: allowsUTF8),
      replacement: replacement,
      alternateDescription: try textProperty(dictionary["Alt"], allowsUTF8: allowsUTF8),
      expansion: try textProperty(dictionary["E"], allowsUTF8: allowsUTF8),
      artifact: artifact,
      values: try Dictionary(uniqueKeysWithValues: dictionary.map {
        ($0.key.bytes, try semanticValue($0.value, depth: 0))
      })
    )
  }

  private func textProperty(_ object: PDFObject?, allowsUTF8: Bool) throws -> String? {
    guard let object else { return nil }
    guard case .string(let value) = object else { throw PDFObjectAccess.TypeMismatch.string }
    return try PDFTextStringDecoder.decode(value, allowsUTF8: allowsUTF8)
  }

  private func nameBytes(_ object: PDFObject?) -> Data? {
    guard case .name(let name)? = object else { return nil }
    return name.bytes
  }

  private func names(_ object: PDFObject?) throws -> [Data] {
    guard let object else { return [] }
    if case .name(let name) = object { return [name.bytes] }
    guard case .array(let values) = object else { throw PDFObjectAccess.TypeMismatch.array }
    return try values.map { try PDFObjectAccess.name($0).bytes }
  }

  private func rectangle(_ object: PDFObject?) throws -> GraphicsRect? {
    guard let object else { return nil }
    let values = try PDFObjectAccess.numbers(object)
    guard values.count == 4 else { throw PDFObjectAccess.TypeMismatch.array }
    return GraphicsRect(
      x: min(values[0], values[2]), y: min(values[1], values[3]),
      width: abs(values[2] - values[0]), height: abs(values[3] - values[1])
    )
  }

  private func semanticValue(_ object: PDFObject, depth: Int) throws -> GraphicsSemanticValue {
    guard depth <= limits.maximumMarkedContentDepth else { throw PDFObjectAccess.TypeMismatch.array }
    switch object {
    case .null: return .null
    case .boolean(let value): return .boolean(value)
    case .number(.integer(let value)): return .integer(value)
    case .number(.real(let value)): return .real(value)
    case .name(let value): return .name(value.bytes)
    case .string(let value): return .string(value.bytes)
    case .array(let values): return .array(try values.map { try semanticValue($0, depth: depth + 1) })
    case .dictionary(let values):
      return .dictionary(try Dictionary(uniqueKeysWithValues: values.map {
        ($0.key.bytes, try semanticValue($0.value, depth: depth + 1))
      }))
    case .reference(let reference):
      return .resource(GraphicsResourceIdentifier(
        rawValue: "pdf:r\(resources.revision.ordinal):o\(reference.objectNumber):\(reference.generationNumber)"
      ))
    }
  }

  private func markedContentEvent(
    _ operation: GraphicsMarkedContentOperation,
    instruction: PDFContentInstruction
  ) -> GraphicsEvent {
    let snapshot = state.snapshot(stroking: false)
    return GraphicsEvent(
      operation: .content(.markedContent(operation)),
      before: snapshot,
      after: snapshot,
      origin: origin(instruction.location)
    )
  }

  private func replaceDeviceRendering(
    transferFunctions: GraphicsTransferFunctions? = nil,
    blackGeneration: GraphicsComponentFunction? = nil,
    undercolorRemoval: GraphicsComponentFunction? = nil,
    halftone: GraphicsHalftone? = nil,
    halftonePhase: GraphicsPoint? = nil
  ) {
    let current = state.deviceRendering
    state.deviceRendering = GraphicsDeviceRenderingSnapshot(
      transferFunctions: transferFunctions ?? current.transferFunctions,
      blackGeneration: blackGeneration ?? current.blackGeneration,
      undercolorRemoval: undercolorRemoval ?? current.undercolorRemoval,
      halftone: halftone ?? current.halftone,
      halftonePhase: halftonePhase ?? current.halftonePhase
    )
  }

  private func setColorState(
    _ color: PDFGraphicsState.ColorState,
    stroking: Bool,
    operation: GraphicsOperation.State,
    location: PDFContentLocation
  ) throws {
    let before = state.snapshot(stroking: stroking)
    if stroking { state.stroking = color } else { state.nonstroking = color }
    try emit(GraphicsEvent(
      operation: .state(operation),
      before: before,
      after: state.snapshot(stroking: stroking),
      origin: origin(location)
    ))
  }

  private func emitState(
    _ operation: GraphicsOperation.State,
    at location: PDFContentLocation,
    mutate: (inout PDFGraphicsState) -> Void
  ) throws {
    let before = state.snapshot(stroking: false)
    mutate(&state)
    try emit(GraphicsEvent(
      operation: .state(operation),
      before: before,
      after: state.snapshot(stroking: false),
      origin: origin(location)
    ))
  }

  private func emitState(
    _ operation: GraphicsOperation.Transform,
    at location: PDFContentLocation,
    mutate: (inout PDFGraphicsState) -> Void
  ) throws {
    let before = state.snapshot(stroking: false)
    mutate(&state)
    try emit(GraphicsEvent(
      operation: .transform(operation),
      before: before,
      after: state.snapshot(stroking: false),
      origin: origin(location)
    ))
  }

  private func emitPath(
    _ operation: GraphicsOperation.Path,
    before: GraphicsStateSnapshot,
    _ instruction: PDFContentInstruction
  ) throws {
    try emit(GraphicsEvent(
      operation: .path(operation),
      before: before,
      after: state.snapshot(stroking: false),
      origin: origin(instruction.location)
    ))
  }

  func operands(_ instruction: PDFContentInstruction, count: Int) throws {
    guard instruction.operands.count == count else { throw malformed("Wrong operand count.", instruction) }
  }

  private func numbers(_ instruction: PDFContentInstruction, count: Int) throws -> [Double] {
    try operands(instruction, count: count)
    return try instruction.operands.map(PDFObjectAccess.number)
  }

  private func integer(_ instruction: PDFContentInstruction, count: Int) throws -> Int {
    try operands(instruction, count: count)
    return try PDFObjectAccess.integer(instruction.operands[0])
  }

  func malformed(_ message: String, _ instruction: PDFContentInstruction) -> PDFGraphicsError {
    .malformedContent(message: message, operatorName: instruction.name, location: instruction.location)
  }

  func origin(
    _ location: PDFContentLocation,
    resource: GraphicsResourceIdentifier? = nil
  ) -> GraphicsEventOrigin {
    let pageIdentifier = GraphicsResourceIdentifier(
      rawValue: "pdf:r\(location.revision.ordinal):o\(location.pageReference.objectNumber):\(location.pageReference.generationNumber)"
    )
    return GraphicsEventOrigin(
      resourceIdentifier: resource ?? pageIdentifier,
      byteSegments: location.segments.map {
        GraphicsEventSourceSegment(
          resourceIdentifier: $0.streamReference.map {
            GraphicsResourceIdentifier(
              rawValue: "pdf:r\(location.revision.ordinal):o\($0.objectNumber):\($0.generationNumber)"
            )
          } ?? pageIdentifier,
          offset: $0.decodedOffset,
          length: Int64($0.decodedLength)
        )
      }
    )
  }

  private static func colorValue(_ paint: GraphicsPaint) -> GraphicsColorValue {
    switch paint {
    case .deviceGray(let value): .deviceGray(value)
    case .deviceRGB(let red, let green, let blue): .deviceRGB(ColorRGB(red: red, green: green, blue: blue))
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      .deviceCMYK(ColorCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black))
    case .color(let value): value
    case .pattern: .deviceGray(0)
    }
  }

  private static func devicePaint(
    space: GraphicsColorSpaceDescription,
    values: [Double]
  ) throws -> GraphicsPaint {
    switch space {
    case .deviceGray: .deviceGray(values[0])
    case .deviceRGB: .deviceRGB(red: values[0], green: values[1], blue: values[2])
    case .deviceCMYK: .deviceCMYK(cyan: values[0], magenta: values[1], yellow: values[2], black: values[3])
    default: throw PDFObjectAccess.TypeMismatch.number
    }
  }

  private static func renderingIntent(_ name: String) -> ColorRenderingIntent? {
    switch name {
    case "AbsoluteColorimetric": .absoluteColorimetric
    case "RelativeColorimetric": .relativeColorimetric
    case "Perceptual": .perceptual
    case "Saturation": .saturation
    default: nil
    }
  }
}
