//
//  PostScriptFileName.swift
//

struct PostScriptFileName {

  let device: String?
  let name: String
  let isUnnamedDevice: Bool

  init(_ source: String) {
    let value = source.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    guard value.first == "%" else {
      self.device = nil
      self.name = value
      self.isUnnamedDevice = false
      return
    }

    let deviceStart = value.index(after: value.startIndex)
    guard let deviceEnd = value[deviceStart...].firstIndex(of: "%") else {
      self.device = String(value[deviceStart...])
      self.name = ""
      self.isUnnamedDevice = true
      return
    }

    self.device = String(value[deviceStart..<deviceEnd])
    self.name = String(value[value.index(after: deviceEnd)...])
    self.isUnnamedDevice = self.name.isEmpty
  }
}
