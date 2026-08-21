import Foundation

struct PostScriptPageDeviceParameters: Sendable {
  let install: Object
  let beginPage: Object
  let endPage: Object
  let policies: Object

  func checkStorage(in vm: VM) throws {
    try install.checkStorage(in: vm)
    try beginPage.checkStorage(in: vm)
    try endPage.checkStorage(in: vm)
    try policies.checkStorage(in: vm)
  }
}
