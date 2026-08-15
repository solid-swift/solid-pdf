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
    GetPosition.instance,
    SetPosition.instance,
    Run.instance,
  ]

  /// Implements the PostScript `file` operator.
  public enum OpenFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["file"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (mode, fileName) = try context.operands.popAs((StringValue, StringValue).self)

      let file = try context.fileDevices.open(name: fileName.string, mode: mode.string)

      context.operands.push(.init(value: FileValue(file: file, vm: context.allocationMode), kind: .literal))
    }
  }

  /// Implements the PostScript `closefile` operator.
  public enum CloseFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["closefile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      try file.file.close()
    }
  }

  /// Implements the PostScript `read` operator.
  public enum Read: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["read"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      if let byte = try file.file.read(max: 1)?.first {
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
    public func execute(context: isolated Context) throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let file = try fileObj.value(as: FileValue.self).file
      let string = try stringObj.value(as: StringValue.self)

      let bytes = try file.read(max: Int(string.count)) ?? Data()

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
    public func execute(context: isolated Context) throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let file = try fileObj.value(as: FileValue.self).file
      let string = try stringObj.value(as: StringValue.self)

      let (bytes, eof) = try file.readHex(max: Int(string.count))

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
    public func execute(context: isolated Context) throws {

      let (stringObj, fileObj) = try context.operands.pop2()
      let file = try fileObj.value(as: FileValue.self).file
      let string = try stringObj.value(as: StringValue.self)

      let (line, eof) = try file.readLine()
      guard line.count <= string.count else {
        throw Error.rangeCheck
      }

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
    public func execute(context: isolated Context) throws {

      let (int, file) = try context.operands.popAs((IntegerValue, FileValue).self)

      let byte = UInt8(clamping: int.value)

      try file.file.write(contentsOf: Data([byte]))
    }
  }

  /// Implements the PostScript `writestring` operator.
  public enum WriteString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["writestring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (string, file) = try context.operands.popAs((StringValue, FileValue).self)

      try file.file.write(contentsOf: string.characters(in: string.range))
    }
  }

  /// Implements the PostScript `writehexstring` operator.
  public enum WriteHexString: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["writehexstring"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (string, file) = try context.operands.popAs((StringValue, FileValue).self)

      try file.file.writeHex(contentsOf: string.characters(in: string.range))
    }
  }

  /// Implements the PostScript `bytesavailable` operator.
  public enum BytesAvailable: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["bytesavailable"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      context.operands.push(try NumericSemantics.integer(validating: file.file.available))
    }
  }

  /// Implements the PostScript `flushfile` operator.
  public enum Flush: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["flushfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      try file.file.flush()
    }
  }

  /// Implements the PostScript `flush` operator.
  public enum FlushStd: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["flush"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let stdout = try context.fileDevices.open(device: "%stdout", name: "", mode: .read, openMethod: .truncateOrCreate)
      try stdout.flush()
    }
  }

  /// Implements the PostScript `resetfile` operator.
  public enum Reset: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["resetfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      try file.file.reset()
    }
  }

  /// Implements the PostScript `status` operator.
  public enum Status: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["status"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      context.operands.push(.boolean(!file.file.isClosed))
    }
  }

  /// Implements the PostScript `fileposition` operator.
  public enum GetPosition: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["fileposition"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: FileValue = try context.operands.popAs()

      context.operands.push(try NumericSemantics.integer(validating: file.file.offset))
    }
  }

  /// Implements the PostScript `setfileposition` operator.
  public enum SetPosition: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["setfileposition"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let (int, file) = try context.operands.popAs((IntegerValue, FileValue).self)

      try file.file.setOffset(Int(int.value))
    }
  }

  /// Implements the PostScript `currentfile` operator.
  public enum CurrentFile: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["currentfile"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      let file: Object =
        if let fileIndex = context.execution.firstIndex(where: { $0.source.type == .file }) {
          context.execution[fileIndex].source
        } else {
          .dataFile(content: Data(), access: .readOnly, vm: .local, kind: .executable)
        }

      context.operands.push(file)
    }
  }

  /// Implements the PostScript `run` operator.
  public enum Run: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["run"]

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) throws {

      context.operands.push(.string("r", access: .unlimited, vm: .local, kind: .literal))

      try OpenFile.instance.execute(context: context)
      try ChangeToExecutable.instance.execute(context: context)
      try Exec.instance.execute(context: context)
    }
  }

}
