import SolidPDF
import SolidPostScript

struct PDFType3GlyphCacheKey: Hashable {
  let fontIdentifier: GraphicsResourceIdentifier
  let procedure: PDFObjectReference
  let code: UInt8
  let transform: GraphicsMatrix
  let nonstrokingState: GraphicsStateSnapshot
  let strokingState: GraphicsStateSnapshot
  let mode: PDFType3GlyphCapture.Mode
}
