import SolidPostScript

struct PDFPagePlan: Sendable {
  let device: GraphicsDeviceSnapshot
  let effects: [GraphicsEffect]
  let copies: Int
}
