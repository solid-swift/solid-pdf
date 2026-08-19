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

private extension GraphicsEffect {
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
      let second = first.partialValue.addingReportingOverflow(256)
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
    case .erase:
      return 128
    }
  }

  func checkedProduct(_ lhs: Int, _ rhs: Int) -> Int? {
    let product = lhs.multipliedReportingOverflow(by: rhs)
    return product.overflow ? nil : product.partialValue
  }
}
