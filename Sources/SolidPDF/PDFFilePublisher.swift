import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PDFFilePublisher {
  static func replace(_ destination: URL, with temporary: URL) throws {
    #if canImport(Darwin) || canImport(Glibc)
    let result = temporary.withUnsafeFileSystemRepresentation { sourcePath in
      destination.withUnsafeFileSystemRepresentation { destinationPath in
        guard let sourcePath, let destinationPath else { return Int32(-1) }
        #if canImport(Darwin)
        return Darwin.rename(sourcePath, destinationPath)
        #else
        return Glibc.rename(sourcePath, destinationPath)
        #endif
      }
    }
    guard result == 0 else { throw PDFError.outputFailure }
    #else
    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    #endif
  }
}
