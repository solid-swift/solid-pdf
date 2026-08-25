import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct PDFXMPParser {
  let limits: PDFParsingLimits

  func parse(_ data: Data) throws -> [PDFMetadataPropertyValue] {
    guard data.count <= limits.maximumMetadataPacketBytes else {
      throw limit("An XMP packet exceeds its configured byte limit.")
    }
    let lexicalText = String(decoding: data, as: UTF8.self).uppercased()
    guard !lexicalText.contains("<!DOCTYPE"), !lexicalText.contains("<!ENTITY") else {
      throw malformed("XMP document types and entity declarations are prohibited.")
    }
    let delegate = Delegate(limits: limits)
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.failure == nil else {
      throw delegate.failure ?? malformed(parser.parserError?.localizedDescription ?? "An XMP packet is malformed.")
    }
    return delegate.properties
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    let limits: PDFParsingLimits
    var properties = [PDFMetadataPropertyValue]()
    var failure: PDFParsingError?
    private var stack = [Element]()

    init(limits: PDFParsingLimits) {
      self.limits = limits
    }

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String]
    ) {
      guard failure == nil else { return }
      guard stack.count < limits.maximumXMPNesting else {
        failure = .limitExceeded(.init(offset: 0, message: "An XMP packet exceeds its nesting limit."))
        parser.abortParsing()
        return
      }
      let name = qName ?? elementName
      let language = attributeDict["xml:lang"] ?? attributeDict["lang"]
      stack.append(Element(name: name, language: language))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard failure == nil, !stack.isEmpty else { return }
      stack[stack.count - 1].text.append(string)
      if stack[stack.count - 1].text.utf8.count > limits.maximumTokenBytes {
        failure = .limitExceeded(.init(offset: 0, message: "An XMP property exceeds its text limit."))
        parser.abortParsing()
      }
    }

    func parser(
      _ parser: XMLParser,
      didEndElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      guard failure == nil, let element = stack.popLast() else { return }
      let value = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        let propertyName = Self.structuralNames.contains(element.name)
          ? stack.last(where: { !Self.structuralNames.contains($0.name) })?.name
          : element.name
        guard let propertyName else { return }
        guard properties.count < limits.maximumXMPProperties else {
          failure = .limitExceeded(.init(offset: 0, message: "An XMP packet contains too many properties."))
          parser.abortParsing()
          return
        }
        properties.append(.init(qualifiedName: propertyName, language: element.language, value: value))
      }
    }

    func parser(
      _ parser: XMLParser,
      foundExternalEntityDeclarationWithName name: String,
      publicID: String?,
      systemID: String?
    ) {
      rejectEntity(parser)
    }

    func parser(
      _ parser: XMLParser,
      foundInternalEntityDeclarationWithName name: String,
      value: String?
    ) {
      rejectEntity(parser)
    }

    func parser(
      _ parser: XMLParser,
      resolveExternalEntityName name: String,
      systemID: String?
    ) -> Data? {
      rejectEntity(parser)
      return nil
    }

    private func rejectEntity(_ parser: XMLParser) {
      failure = .malformed(.init(offset: 0, message: "XMP entity declarations are prohibited."))
      parser.abortParsing()
    }

    private struct Element {
      let name: String
      let language: String?
      var text = ""
    }

    private static let structuralNames: Set<String> = [
      "x:xmpmeta", "xmpmeta", "rdf:RDF", "RDF", "rdf:Description", "Description",
      "rdf:Alt", "Alt", "rdf:Bag", "Bag", "rdf:Seq", "Seq", "rdf:li", "li",
    ]
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }

  private func limit(_ message: String) -> PDFParsingError {
    .limitExceeded(.init(offset: 0, message: message))
  }
}
