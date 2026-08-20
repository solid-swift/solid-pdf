import Foundation
import SolidColor

indirect enum PostScriptColorSpace: Sendable, Hashable {
  struct CIE: Sendable, Hashable {
    enum InitialTransform: Sendable, Hashable {
      case matrix([Double])
      case lookup(inputRange: [ColorComponentRange], table: ColorLookupTable)
    }

    let whitePoint: ColorXYZ
    let blackPoint: ColorXYZ
    let range: [ColorComponentRange]
    let decode: [Object]
    let initialTransform: InitialTransform
    let rangeABC: [ColorComponentRange]
    let decodeABC: [Object]
    let matrixABC: [Double]
    let rangeLMN: [ColorComponentRange]
    let decodeLMN: [Object]
    let matrixLMN: [Double]
  }

  case deviceGray(Object?)
  case deviceRGB(Object?)
  case deviceCMYK(Object?)
  case cieA(source: Object, parameters: CIE)
  case cieABC(source: Object, parameters: CIE)
  case cieDEF(source: Object, parameters: CIE)
  case cieDEFG(source: Object, parameters: CIE)
  case indexed(source: Object, base: Self, maximumIndex: Int, lookup: Object)
  case separation(source: Object, name: String, alternative: Self, transform: Object)
  case deviceN(source: Object, names: [String], alternative: Self, transform: Object)
  case pattern(source: Object, underlying: Self?)

  var source: Object? {
    switch self {
    case .deviceGray(let source), .deviceRGB(let source), .deviceCMYK(let source): source
    case .cieA(let source, _), .cieABC(let source, _), .cieDEF(let source, _), .cieDEFG(let source, _),
         .indexed(let source, _, _, _), .separation(let source, _, _, _), .deviceN(let source, _, _, _),
         .pattern(let source, _): source
    }
  }

  var description: GraphicsColorSpaceDescription {
    switch self {
    case .deviceGray: .deviceGray
    case .deviceRGB: .deviceRGB
    case .deviceCMYK: .deviceCMYK
    case .cieA(_, let parameters): .cieBasedA(whitePoint: parameters.whitePoint)
    case .cieABC(_, let parameters): .cieBasedABC(whitePoint: parameters.whitePoint)
    case .cieDEF(_, let parameters): .cieBasedDEF(whitePoint: parameters.whitePoint)
    case .cieDEFG(_, let parameters): .cieBasedDEFG(whitePoint: parameters.whitePoint)
    case .indexed(_, let base, let maximumIndex, _): .indexed(base: base.description, maximumIndex: maximumIndex)
    case .separation(_, let name, let alternative, _): .separation(name: name, alternative: alternative.description)
    case .deviceN(_, let names, let alternative, _): .deviceN(names: names, alternative: alternative.description)
    case .pattern(_, let underlying): .pattern(underlying: underlying?.description)
    }
  }

  var componentCount: Int { description.componentCount }

  func normalized(_ components: [Double]) -> [Double] {
    switch self {
    case .deviceGray, .deviceRGB, .deviceCMYK, .separation, .deviceN:
      return components.map { min(1, max(0, $0)) }
    case .cieA(_, let parameters), .cieABC(_, let parameters), .cieDEF(_, let parameters),
         .cieDEFG(_, let parameters):
      return zip(components, parameters.range).map { $1.clamp($0) }
    case .indexed(_, _, let maximumIndex, _):
      return [min(Double(maximumIndex), max(0, components[0].rounded()))]
    case .pattern(_, let underlying):
      return underlying?.normalized(components) ?? []
    }
  }

  var initialComponents: [Double] {
    switch self {
    case .deviceGray, .deviceRGB, .indexed:
      Array(repeating: 0, count: componentCount)
    case .deviceCMYK:
      [0, 0, 0, 1]
    case .cieA(_, let parameters), .cieABC(_, let parameters), .cieDEF(_, let parameters),
         .cieDEFG(_, let parameters):
      parameters.range.map { $0.clamp(0) }
    case .separation, .deviceN:
      Array(repeating: 1, count: componentCount)
    case .pattern(_, let underlying):
      underlying?.initialComponents ?? []
    }
  }

  var retainedObjects: [Object] {
    var result = source.map { [$0] } ?? []
    switch self {
    case .cieA(_, let value), .cieABC(_, let value), .cieDEF(_, let value), .cieDEFG(_, let value):
      result.append(contentsOf: value.decode + value.decodeABC + value.decodeLMN)
    case .indexed(_, let base, _, let lookup):
      result.append(contentsOf: base.retainedObjects)
      result.append(lookup)
    case .separation(_, _, let alternate, let transform), .deviceN(_, _, let alternate, let transform):
      result.append(contentsOf: alternate.retainedObjects)
      result.append(transform)
    case .pattern(_, let underlying):
      if let underlying { result.append(contentsOf: underlying.retainedObjects) }
    case .deviceGray, .deviceRGB, .deviceCMYK:
      break
    }
    return result
  }
}

indirect enum VMStoredColorSpace: Sendable {
  struct CIE: Sendable {
    let whitePoint: ColorXYZ
    let blackPoint: ColorXYZ
    let range: [ColorComponentRange]
    let initialTransform: PostScriptColorSpace.CIE.InitialTransform
    let rangeABC: [ColorComponentRange]
    let matrixABC: [Double]
    let rangeLMN: [ColorComponentRange]
    let matrixLMN: [Double]
    let decode: [VMStoredObject]
    let decodeABC: [VMStoredObject]
    let decodeLMN: [VMStoredObject]

    init(_ value: PostScriptColorSpace.CIE) {
      self.whitePoint = value.whitePoint
      self.blackPoint = value.blackPoint
      self.range = value.range
      self.initialTransform = value.initialTransform
      self.rangeABC = value.rangeABC
      self.matrixABC = value.matrixABC
      self.rangeLMN = value.rangeLMN
      self.matrixLMN = value.matrixLMN
      self.decode = value.decode.map(VMStoredObject.init)
      self.decodeABC = value.decodeABC.map(VMStoredObject.init)
      self.decodeLMN = value.decodeLMN.map(VMStoredObject.init)
    }

    var colorValue: PostScriptColorSpace.CIE {
      .init(
        whitePoint: whitePoint,
        blackPoint: blackPoint,
        range: range,
        decode: decode.map(\.requiredObject),
        initialTransform: initialTransform,
        rangeABC: rangeABC,
        decodeABC: decodeABC.map(\.requiredObject),
        matrixABC: matrixABC,
        rangeLMN: rangeLMN,
        decodeLMN: decodeLMN.map(\.requiredObject),
        matrixLMN: matrixLMN
      )
    }

    var storedObjects: [VMStoredObject] { decode + decodeABC + decodeLMN }
  }

  case deviceGray(VMStoredObject?)
  case deviceRGB(VMStoredObject?)
  case deviceCMYK(VMStoredObject?)
  case cieA(source: VMStoredObject, parameters: CIE)
  case cieABC(source: VMStoredObject, parameters: CIE)
  case cieDEF(source: VMStoredObject, parameters: CIE)
  case cieDEFG(source: VMStoredObject, parameters: CIE)
  case indexed(source: VMStoredObject, base: Self, maximumIndex: Int, lookup: VMStoredObject)
  case separation(
    source: VMStoredObject,
    name: String,
    alternative: Self,
    transform: VMStoredObject
  )
  case deviceN(
    source: VMStoredObject,
    names: [String],
    alternative: Self,
    transform: VMStoredObject
  )
  case pattern(source: VMStoredObject, underlying: Self?)

  init(_ value: PostScriptColorSpace) {
    switch value {
    case .deviceGray(let source): self = .deviceGray(source.map(VMStoredObject.init))
    case .deviceRGB(let source): self = .deviceRGB(source.map(VMStoredObject.init))
    case .deviceCMYK(let source): self = .deviceCMYK(source.map(VMStoredObject.init))
    case .cieA(let source, let parameters):
      self = .cieA(source: VMStoredObject(source), parameters: CIE(parameters))
    case .cieABC(let source, let parameters):
      self = .cieABC(source: VMStoredObject(source), parameters: CIE(parameters))
    case .cieDEF(let source, let parameters):
      self = .cieDEF(source: VMStoredObject(source), parameters: CIE(parameters))
    case .cieDEFG(let source, let parameters):
      self = .cieDEFG(source: VMStoredObject(source), parameters: CIE(parameters))
    case .indexed(let source, let base, let maximumIndex, let lookup):
      self = .indexed(
        source: VMStoredObject(source),
        base: Self(base),
        maximumIndex: maximumIndex,
        lookup: VMStoredObject(lookup)
      )
    case .separation(let source, let name, let alternative, let transform):
      self = .separation(
        source: VMStoredObject(source),
        name: name,
        alternative: Self(alternative),
        transform: VMStoredObject(transform)
      )
    case .deviceN(let source, let names, let alternative, let transform):
      self = .deviceN(
        source: VMStoredObject(source),
        names: names,
        alternative: Self(alternative),
        transform: VMStoredObject(transform)
      )
    case .pattern(let source, let underlying):
      self = .pattern(source: VMStoredObject(source), underlying: underlying.map(Self.init))
    }
  }

  var colorSpace: PostScriptColorSpace {
    switch self {
    case .deviceGray(let source): .deviceGray(source?.requiredObject)
    case .deviceRGB(let source): .deviceRGB(source?.requiredObject)
    case .deviceCMYK(let source): .deviceCMYK(source?.requiredObject)
    case .cieA(let source, let parameters):
      .cieA(source: source.requiredObject, parameters: parameters.colorValue)
    case .cieABC(let source, let parameters):
      .cieABC(source: source.requiredObject, parameters: parameters.colorValue)
    case .cieDEF(let source, let parameters):
      .cieDEF(source: source.requiredObject, parameters: parameters.colorValue)
    case .cieDEFG(let source, let parameters):
      .cieDEFG(source: source.requiredObject, parameters: parameters.colorValue)
    case .indexed(let source, let base, let maximumIndex, let lookup):
      .indexed(
        source: source.requiredObject,
        base: base.colorSpace,
        maximumIndex: maximumIndex,
        lookup: lookup.requiredObject
      )
    case .separation(let source, let name, let alternative, let transform):
      .separation(
        source: source.requiredObject,
        name: name,
        alternative: alternative.colorSpace,
        transform: transform.requiredObject
      )
    case .deviceN(let source, let names, let alternative, let transform):
      .deviceN(
        source: source.requiredObject,
        names: names,
        alternative: alternative.colorSpace,
        transform: transform.requiredObject
      )
    case .pattern(let source, let underlying):
      .pattern(source: source.requiredObject, underlying: underlying?.colorSpace)
    }
  }

  var storedObjects: [VMStoredObject] {
    switch self {
    case .deviceGray(let source), .deviceRGB(let source), .deviceCMYK(let source):
      source.map { [$0] } ?? []
    case .cieA(let source, let parameters), .cieABC(let source, let parameters),
         .cieDEF(let source, let parameters), .cieDEFG(let source, let parameters):
      [source] + parameters.storedObjects
    case .indexed(let source, let base, _, let lookup):
      [source, lookup] + base.storedObjects
    case .separation(let source, _, let alternative, let transform),
         .deviceN(let source, _, let alternative, let transform):
      [source, transform] + alternative.storedObjects
    case .pattern(let source, let underlying):
      [source] + (underlying?.storedObjects ?? [])
    }
  }

  func identifyEdges(from allocation: VMAllocation) {
    storedObjects.forEach { $0.identifyEdgeSource(allocation) }
  }

  func refreshEdges() {
    storedObjects.forEach { $0.refreshEdge() }
  }
}

extension VMStoredObject {
  fileprivate var requiredObject: Object { object }
}
