import Foundation

final class GraphicsDisplayListCollector: GraphicsEventConsumer {
  private(set) var effects: [GraphicsEffect] = []
  private var activeImage: (
    descriptor: GraphicsImageDescriptor,
    state: GraphicsStateSnapshot,
    components: [Float],
    sourceComponents: [Float],
    maskOpacities: [Float],
    nextMaskRow: Int
  )?

  func process(_ event: GraphicsEvent) throws {
    switch event.operation {
    case .paint(.erasePage):
      effects.append(.erase(state: event.before))
    case .paint(.fill(let rule)):
      effects.append(.fill(path: event.before.path, rule: rule, state: event.before))
    case .paint(.stroke):
      effects.append(.stroke(path: event.before.path, state: event.before))
    case .paint(.userPathFill(let rule)):
      effects.append(.userPathFill(path: event.before.path, rule: rule, state: event.before))
    case .paint(.userPathStroke):
      effects.append(.userPathStroke(outline: event.before.path, state: event.before))
    case .paint(.fillRectangles(let paths)):
      effects.append(.fillRectangles(paths: paths, state: event.before))
    case .paint(.strokeRectangles(let paths, let matrix)):
      effects.append(.strokeRectangles(paths: paths, matrix: matrix, state: event.before))
    case .paint(.shading(let shading)):
      effects.append(.shading(shading, state: event.before))
    case .paint(.form(let form)):
      effects.append(.form(form, state: event.before))
    case .page:
      throw Error.undefined
    default:
      break
    }
  }

  func beginImage(_ event: GraphicsEvent) throws {
    guard activeImage == nil, case .paint(.image(let descriptor)) = event.operation else {
      throw Error.ioError
    }
    activeImage = (descriptor, event.before, [], [], [], 0)
  }

  func writeImageRows(_ rows: GraphicsImageRows) throws {
    guard var image = activeImage else { throw Error.ioError }
    image.components.append(contentsOf: rows.components)
    if let source = rows.sourceComponents { image.sourceComponents.append(contentsOf: source) }
    activeImage = image
  }

  func writeImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    guard var image = activeImage,
      let dimensions = maskDimensions(for: image.descriptor),
      dimensions.width > 0,
      dimensions.height > 0,
      rows.rowCount > 0,
      rows.startRow == image.nextMaskRow,
      rows.rowCount <= dimensions.height - image.nextMaskRow,
      rows.rowCount <= Int.max / dimensions.width,
      rows.opacities.count == rows.rowCount * dimensions.width
    else { throw Error.ioError }
    image.maskOpacities.append(contentsOf: rows.opacities)
    image.nextMaskRow += rows.rowCount
    activeImage = image
  }

  func endImage() throws {
    guard let image = activeImage else { throw Error.ioError }
    effects.append(.image(
      GraphicsImage(
        descriptor: image.descriptor,
        components: image.components,
        sourceComponents: image.sourceComponents.isEmpty ? nil : image.sourceComponents,
        mask: image.descriptor.mask.map {
          GraphicsImageMask(descriptor: $0, opacities: image.maskOpacities)
        }
      ),
      state: image.state
    ))
    activeImage = nil
  }

  func abortImage() { activeImage = nil }

  func abort() {
    activeImage = nil
    effects.removeAll()
  }

  private func maskDimensions(for descriptor: GraphicsImageDescriptor) -> (width: Int, height: Int)? {
    switch descriptor.mask {
    case .explicit(let width, let height, _, _): (width, height)
    case .colorKey: (descriptor.width, descriptor.height)
    case nil: nil
    }
  }
}
