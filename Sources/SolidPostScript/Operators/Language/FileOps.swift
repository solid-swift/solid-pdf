//
//  FileOps.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation

extension Operators {

  static let fileOps: [OperatorValue] = [
    OpenFile.instance,
    CloseFile.instance,
    Read.instance,
    ReadString.instance,
    ReadHexString.instance,
    ReadLine.instance,
    Write.instance,
    WriteString.instance,
    WriteHexString.instance,
    BytesAvailable.instance,
    Flush.instance,
    FlushStd.instance,
    Reset.instance,
    Status.instance,
    DeleteFile.instance,
    RenameFile.instance,
    FilenameForAll.instance,
    GetPosition.instance,
    SetPosition.instance,
    CurrentFile.instance,
    Run.instance,
  ]

  /// Implements the PostScript `file` operator.
  public enum OpenFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["file"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (mode, fileName) = try context.operands.popAs((StringValue, StringValue).self)

      let modeString = try mode.readableString
      let fileNameString = try fileName.readableString

      let file: any File
      switch fileNameString {
      case "%lineedit":
        guard modeString == "r" else { throw Error.invalidFileAccess }
        file = try await context.openInteractiveFile(statement: false)
      case "%statementedit":
        guard modeString == "r" else { throw Error.invalidFileAccess }
        file = try await context.openInteractiveFile(statement: true)
      default:
        file = try context.openFile(name: fileNameString, mode: modeString)
      }

      let vm = context.allocationMode
      let allocation = context.register(file: file, vm: vm)
      context.operands.push(.file(file, access: file.mode.access, vm: vm, allocation: allocation, kind: .literal))
    }
  }

  /// Implements the PostScript `closefile` operator.
  public enum CloseFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["closefile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      try await file.file.close(context: context)
    }
  }

  /// Implements the PostScript `read` operator.
  public enum Read: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["read"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      try file.checkReadable()

      if let byte = try await file.file.read(max: 1, context: context)?.first {
        context.operands.push(.integer(Int32(byte)), .boolean(true))
      } else {
        context.operands.push(.boolean(false))
      }
    }
  }

  /// Implements the PostScript `readstring` operator.
  public enum ReadString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["readstring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let fileValue = try fileObj.value(as: FileValue.self)
      let string = try stringObj.value(as: StringValue.self)

      try fileValue.checkReadable()
      try string.access.check(.write)
      guard string.count > 0 else {
        throw Error.rangeCheck
      }

      let bytes = try await fileValue.file.read(max: Int(string.count), context: context) ?? Data()

      try string.updateCharacters(bytes, startingAt: 0)
      let subRange = 0..<UInt(bytes.count)

      let eof = string.count > bytes.count

      context.operands.push(.boolean(!eof), try .string(sharing: string, subRange: subRange, kind: stringObj.kind))
    }
  }

  /// Implements the PostScript `readhexstring` operator.
  public enum ReadHexString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["readhexstring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let fileValue = try fileObj.value(as: FileValue.self)
      let string = try stringObj.value(as: StringValue.self)

      try fileValue.checkReadable()
      try string.access.check(.write)

      let (bytes, eof) = try await fileValue.file.readHex(max: Int(string.count), context: context)

      try string.updateCharacters(bytes, startingAt: 0)
      let subRange = 0..<UInt(bytes.count)

      context.operands.push(.boolean(!eof), try .string(sharing: string, subRange: subRange, kind: stringObj.kind))
    }
  }

  /// Implements the PostScript `readline` operator.
  public enum ReadLine: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["readline"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let fileValue = try fileObj.value(as: FileValue.self)
      let string = try stringObj.value(as: StringValue.self)

      try fileValue.checkReadable()
      try string.access.check(.write)

      let (line, eof) = try await fileValue.file.readLine(max: Int(string.count), context: context)

      try string.updateCharacters(line, startingAt: 0)
      let subRange = 0..<UInt(line.count)

      context.operands.push(.boolean(!eof), try .string(sharing: string, subRange: subRange, kind: stringObj.kind))
    }
  }

  /// Implements the PostScript `write` operator.
  public enum Write: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["write"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (int, file) = try context.operands.popAs((IntegerValue, FileValue).self)

      try file.checkWritable()

      let byte = UInt8(truncatingIfNeeded: int.value)

      try await file.file.write(contentsOf: Data([byte]), context: context)
    }
  }

  /// Implements the PostScript `writestring` operator.
  public enum WriteString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["writestring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (string, file) = try context.operands.popAs((StringValue, FileValue).self)

      try file.checkWritable()
      try string.access.check(.read)

      try await file.file.write(contentsOf: string.characters(in: string.range), context: context)
    }
  }

  /// Implements the PostScript `writehexstring` operator.
  public enum WriteHexString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["writehexstring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (string, file) = try context.operands.popAs((StringValue, FileValue).self)

      try file.checkWritable()
      try string.access.check(.read)

      let data = try string.characters(in: string.range)
      try await file.file.write(contentsOf: Data(data.baseEncoded(using: .base16Lower).utf8), context: context)
    }
  }

  /// Implements the PostScript `bytesavailable` operator.
  public enum BytesAvailable: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["bytesavailable"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      try file.checkReadable()

      context.operands.push(try NumericSemantics.integer(validating: await file.file.available(context: context)))
    }
  }

  /// Implements the PostScript `flushfile` operator.
  public enum Flush: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["flushfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      try await file.file.flush(context: context)
    }
  }

  /// Implements the PostScript `flush` operator.
  public enum FlushStd: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["flush"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      try await context.flushStandardOutput()
    }
  }

  /// Implements the PostScript `resetfile` operator.
  public enum Reset: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["resetfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      do {
        try context.reset(file: file.file)
      } catch Error.ioError {
        // resetfile is best-effort and never reports an I/O error.
      }
    }
  }

  /// Implements the PostScript `status` operator.
  public enum Status: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["status"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let operand = try context.operands.pop()
      if let file = operand.value as? FileValue {
        context.operands.push(.boolean(!file.file.isClosed))
        return
      }

      let name = try operand.value(as: StringValue.self)
      let nameString = try name.readableString

      guard let status = try? context.fileDevices.status(name: nameString) else {
        context.operands.push(.boolean(false))
        return
      }

      context.operands.push(
        .integer(status.pages),
        .integer(status.bytes),
        .integer(status.referenced),
        .integer(status.created),
        .boolean(true)
      )
    }
  }

  /// Implements the PostScript `deletefile` operator.
  public enum DeleteFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["deletefile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let name: StringValue = try context.operands.popAs()
      try context.fileDevices.delete(name: name.readableString)
    }
  }

  /// Implements the PostScript `renamefile` operator.
  public enum RenameFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["renamefile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (newName, oldName) = try context.operands.popAs((StringValue, StringValue).self)
      let oldNameString = try oldName.readableString
      let newNameString = try newName.readableString
      try context.fileDevices.rename(name: oldNameString, to: newNameString)
    }
  }

  /// Implements the PostScript `filenameforall` operator.
  public enum FilenameForAll: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["filenameforall"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (scratchObject, proc, templateObject) = try context.operands.pop3()
      let scratch = try scratchObject.value(as: StringValue.self)
      let template = try templateObject.value(as: StringValue.self)
      try scratch.access.check(.write)
      let templateString = try template.readableString
      try proc.checkProcedure()

      let names = try context.fileDevices.fileNames(matching: templateString)
      for name in names {
        guard let bytes = name.data(using: .isoLatin1), bytes.count <= scratch.count else {
          throw Error.rangeCheck
        }
        try scratch.updateCharacters(bytes, startingAt: 0)
        let argument = try Object.string(sharing: scratch, subRange: 0..<UInt(bytes.count), kind: .literal)
        if try await !context.execute(proc: proc, ops: [argument]) { break }
      }
    }
  }

  /// Implements the PostScript `fileposition` operator.
  public enum GetPosition: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["fileposition"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: FileValue = try context.operands.popAs()

      guard file.file.isPositionable else { throw Error.ioError }

      context.operands.push(try NumericSemantics.integer(validating: context.logicalOffset(in: file.file)))
    }
  }

  /// Implements the PostScript `setfileposition` operator.
  public enum SetPosition: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setfileposition"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let (int, file) = try context.operands.popAs((IntegerValue, FileValue).self)

      guard int.value >= 0 else {
        throw Error.rangeCheck
      }

      guard file.file.isPositionable else { throw Error.ioError }

      try context.setLogicalOffset(Int(int.value), in: file.file)
    }
  }

  /// Implements the PostScript `currentfile` operator.
  public enum CurrentFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      let file: Object =
        if let fileIndex = context.execution.firstIndex(where: { $0.source.type == .file }) {
          .init(value: context.execution[fileIndex].source.value, kind: .literal)
        } else {
          try invalidFile()
        }

      context.operands.push(file)
    }

    private func invalidFile() throws -> Object {
      let file = DataFile(data: Data(), mode: .read)
      try file.close()
      return .file(file, access: .readOnly, vm: .local, kind: .literal)
    }
  }

  /// Implements the PostScript `run` operator.
  public enum Run: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["run"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {

      context.operands.push(.string("r", access: .unlimited, vm: .local, kind: .literal))

      try await OpenFile.instance.execute(context: context)
      try await ChangeToExecutable.instance.execute(context: context)
      try await Exec.instance.execute(context: context)
    }
  }

}
