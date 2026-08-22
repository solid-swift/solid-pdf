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

  var diagnostics: [PDFGraphicsDiagnostic] { diagnosticsStorage }
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
    initialState: PDFGraphicsState? = nil
  ) {
    state = initialState ?? PDFGraphicsState(device: device)
    self.resources = resources
    self.limits = limits
    self.output = output
  }

  private func emit(_ event: GraphicsEvent) throws { try output.process(event) }

  func execute(_ instruction: PDFContentInstruction) async throws {
    do {
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
      case "BT", "ET": try operands(instruction, count: 0)
      case "Tc", "Tw", "Tz", "TL", "Tr", "Ts": _ = try numbers(instruction, count: 1)
      case "Tf":
        try operands(instruction, count: 2)
        _ = try PDFObjectAccess.name(instruction.operands[0])
        _ = try PDFObjectAccess.number(instruction.operands[1])
      case "Td", "TD": _ = try numbers(instruction, count: 2)
      case "Tm": _ = try numbers(instruction, count: 6)
      case "T*": try operands(instruction, count: 0)
      case "Tj", "TJ", "'", "\"":
        throw PDFGraphicsError.unsupported(.textPainting, location: instruction.location)
      case "BMC", "BDC", "EMC", "MP", "DP":
        try validateMarkedContent(instruction)
      case "Do": try await paintXObject(instruction)
      case "sh": try await paintShading(instruction)
      case "BI": throw PDFGraphicsError.unsupported(.operatorName("BI"), location: instruction.location)
      case "d0", "d1": throw PDFGraphicsError.unsupported(.operatorName(instruction.name), location: instruction.location)
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
    guard stack.isEmpty else {
      throw PDFGraphicsError.malformedContent(
        message: "PDF graphics-state stack is not balanced.",
        operatorName: "q",
        location: location!
      )
    }
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
      guard case .name(let name) = value, name.pdfGraphicsString == "Default" else {
        throw PDFGraphicsError.unsupported(.operatorName("ExtGState.HT"), location: instruction.location)
      }
      replaceDeviceRendering(halftone: state.device.descriptor.deviceRendering.defaultState.halftone)
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

  private func validateMarkedContent(_ instruction: PDFContentInstruction) throws {
    if instruction.name == "BDC" || instruction.name == "DP", instruction.operands.count == 2,
      case .name(let property) = instruction.operands[1],
      property.pdfGraphicsString == "OC"
    {
      throw PDFGraphicsError.unsupported(.optionalContent, location: instruction.location)
    }
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
