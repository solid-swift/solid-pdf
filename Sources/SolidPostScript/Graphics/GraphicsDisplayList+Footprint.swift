import Foundation

extension GraphicsDisplayList {
  func checkedFootprint(maximumDepth: Int = 16) -> Int {
    checkedFootprint(depth: 0, maximumDepth: maximumDepth) ?? .max
  }

  fileprivate func checkedFootprint(depth: Int, maximumDepth: Int) -> Int? {
    guard depth <= maximumDepth else { return nil }
    return effects.reduce(256) { partial, effect in
      guard let effectBytes = effect.checkedFootprint(depth: depth, maximumDepth: maximumDepth) else { return .max }
      let sum = partial.addingReportingOverflow(effectBytes)
      return sum.overflow ? .max : sum.partialValue
    }
  }
}

package struct GraphicsStorageFootprint: Sendable, Equatable {
  package let displayBytes: Int
  package let sourceBytes: Int

  package static let zero = GraphicsStorageFootprint(displayBytes: 0, sourceBytes: 0)

  package func adding(_ other: Self) -> Self? {
    let display = displayBytes.addingReportingOverflow(other.displayBytes)
    let source = sourceBytes.addingReportingOverflow(other.sourceBytes)
    guard !display.overflow, !source.overflow else { return nil }
    return Self(displayBytes: display.partialValue, sourceBytes: source.partialValue)
  }
}

package extension GraphicsDisplayList {
  func storageFootprint(maximumDepth: Int = 16) -> GraphicsStorageFootprint? {
    guard maximumDepth >= 0 else { return nil }
    return effects.reduce(GraphicsStorageFootprint(displayBytes: 256, sourceBytes: 0)) { partial, effect in
      guard let footprint = effect.storageFootprint(depth: 0, maximumDepth: maximumDepth) else {
        return GraphicsStorageFootprint(displayBytes: .max, sourceBytes: .max)
      }
      return partial.adding(footprint) ?? GraphicsStorageFootprint(displayBytes: .max, sourceBytes: .max)
    }
  }
}

private extension GraphicsEffect {
  func storageFootprint(depth: Int, maximumDepth: Int) -> GraphicsStorageFootprint? {
    switch self {
    case .fill(let path, _, _), .stroke(let path, _), .userPathFill(let path, _, _),
         .userPathStroke(let path, _):
      guard let elements = checkedProduct(path.elements.count, 56) else { return nil }
      return GraphicsStorageFootprint(displayBytes: elements + 256, sourceBytes: 0)
    case .fillRectangles(let paths, _), .strokeRectangles(let paths, _, _):
      let bytes = paths.reduce(256) { partial, path in
        guard let elements = checkedProduct(path.elements.count, 56) else { return .max }
        let total = partial.addingReportingOverflow(elements)
        return total.overflow ? .max : total.partialValue
      }
      return bytes == .max ? nil : GraphicsStorageFootprint(displayBytes: bytes, sourceBytes: 0)
    case .image(let image, _):
      guard let components = checkedProduct(image.components.count, MemoryLayout<Float>.stride),
        let source = checkedProduct(image.sourceComponents?.count ?? 0, MemoryLayout<Float>.stride),
        let mask = checkedProduct(image.mask?.opacities.count ?? 0, MemoryLayout<Float>.stride)
      else { return nil }
      let first = components.addingReportingOverflow(source)
      let second = first.partialValue.addingReportingOverflow(mask)
      guard !first.overflow, !second.overflow else { return nil }
      return GraphicsStorageFootprint(displayBytes: 256, sourceBytes: second.partialValue)
    case .shading(let shading, _):
      guard let triangles = checkedProduct(
        shading.mesh.triangles.count,
        MemoryLayout<GraphicsShadingTriangle>.stride
      ) else { return nil }
      return GraphicsStorageFootprint(displayBytes: triangles + 256, sourceBytes: 0)
    case .form:
      // Cached form bodies are governed by MaxFormCache. A page display list retains only a reference.
      return GraphicsStorageFootprint(displayBytes: 128, sourceBytes: 0)
    case .text(let run, _):
      var result = GraphicsStorageFootprint(displayBytes: 256, sourceBytes: 0)
      for placement in run.glyphs {
        let glyph: GraphicsStorageFootprint
        switch placement.glyph.program {
        case .outline(let path):
          guard let bytes = checkedProduct(path.elements.count, 56) else { return nil }
          glyph = GraphicsStorageFootprint(displayBytes: bytes, sourceBytes: 0)
        case .bitmap(let bitmap):
          glyph = GraphicsStorageFootprint(displayBytes: 32, sourceBytes: bitmap.coverage.count)
        case .displayList(let list):
          guard depth < maximumDepth,
            let nested = list.effects.reduce(Optional(GraphicsStorageFootprint.zero), { partial, effect in
              guard let partial, let next = effect.storageFootprint(depth: depth + 1, maximumDepth: maximumDepth)
              else { return nil }
              return partial.adding(next)
            })
          else { return nil }
          glyph = nested
        case .empty, .missing:
          glyph = GraphicsStorageFootprint(displayBytes: 32, sourceBytes: 0)
        }
        guard let combined = result.adding(glyph) else { return nil }
        result = combined
      }
      return result
    case .erase:
      return GraphicsStorageFootprint(displayBytes: 128, sourceBytes: 0)
    }
  }

  func checkedFootprint(depth: Int, maximumDepth: Int) -> Int? {
    switch self {
    case .fill(let path, _, _), .stroke(let path, _), .userPathFill(let path, _, _),
         .userPathStroke(let path, _):
      guard let elementBytes = checkedProduct(path.elements.count, 56) else { return nil }
      let result = elementBytes.addingReportingOverflow(256)
      return result.overflow ? nil : result.partialValue
    case .fillRectangles(let paths, _), .strokeRectangles(let paths, _, _):
      return paths.reduce(256) { partial, path in
        guard let elementBytes = checkedProduct(path.elements.count, 56) else { return .max }
        let total = partial.addingReportingOverflow(elementBytes)
        return total.overflow ? .max : total.partialValue
      }
    case .image(let image, _):
      guard let componentBytes = checkedProduct(image.components.count, MemoryLayout<Float>.stride),
        let sourceBytes = checkedProduct(image.sourceComponents?.count ?? 0, MemoryLayout<Float>.stride)
      else { return nil }
      let first = componentBytes.addingReportingOverflow(sourceBytes)
      guard !first.overflow else { return nil }
      guard let maskBytes = checkedProduct(image.mask?.opacities.count ?? 0, MemoryLayout<Float>.stride) else {
        return nil
      }
      let masked = first.partialValue.addingReportingOverflow(maskBytes)
      guard !masked.overflow else { return nil }
      let second = masked.partialValue.addingReportingOverflow(256)
      return second.overflow ? nil : second.partialValue
    case .shading(let shading, _):
      guard let triangleBytes = checkedProduct(
        shading.mesh.triangles.count,
        MemoryLayout<GraphicsShadingTriangle>.stride
      ) else { return nil }
      let result = triangleBytes.addingReportingOverflow(256)
      return result.overflow ? nil : result.partialValue
    case .form(let form, _):
      guard depth < maximumDepth else { return nil }
      return form.displayList.checkedFootprint(depth: depth + 1, maximumDepth: maximumDepth)
    case .text(let run, _):
      return run.glyphs.reduce(256) { partial, placement in
        let bytes: Int
        switch placement.glyph.program {
        case .outline(let path):
          let product = path.elements.count.multipliedReportingOverflow(by: 56)
          bytes = product.overflow ? .max : product.partialValue
        case .bitmap(let bitmap):
          bytes = bitmap.coverage.count
        case .displayList(let list):
          bytes = list.checkedFootprint()
        case .empty, .missing:
          bytes = 32
        }
        let total = partial.addingReportingOverflow(bytes)
        return total.overflow ? .max : total.partialValue
      }
    case .erase:
      return 128
    }
  }

  func checkedProduct(_ lhs: Int, _ rhs: Int) -> Int? {
    let product = lhs.multipliedReportingOverflow(by: rhs)
    return product.overflow ? nil : product.partialValue
  }
}
