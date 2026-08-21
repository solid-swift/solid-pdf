extension Context {
  func beginEExecScope(for file: EExecFile) throws {
    try dictionaries.preflightPush()
    let savedDictionaries = dictionaries
    try dictionaries.push(dictionaries.systemDictionaryObject())
    eexecScopes.append(EExecExecutionScope(file: file, dictionaries: savedDictionaries))
  }

  func closeEExecScope(for file: EExecFile) {
    guard let index = eexecScopes.lastIndex(where: { $0.file === file }) else { return }
    eexecScopes[index].closed = true
    while let scope = eexecScopes.last, scope.closed {
      dictionaries = scope.dictionaries
      eexecScopes.removeLast()
    }
  }
}

struct EExecExecutionScope {
  let file: EExecFile
  let dictionaries: DictionaryStack
  var closed = false
}
