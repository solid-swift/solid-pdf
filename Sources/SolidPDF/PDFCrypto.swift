import Crypto
import CryptoExtras
import Foundation

enum PDFCrypto {
  static func md5(_ data: Data) -> Data {
    Data(Insecure.MD5.hash(data: data))
  }

  static func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  static func sha384(_ data: Data) -> Data {
    Data(SHA384.hash(data: data))
  }

  static func sha512(_ data: Data) -> Data {
    Data(SHA512.hash(data: data))
  }

  static func aesCBCDecrypt(
    _ ciphertext: Data,
    key: Data,
    initializationVector: Data,
    removesPadding: Bool
  ) throws -> Data {
    try AES._CBC.decrypt(
      ciphertext,
      using: SymmetricKey(data: key),
      iv: try AES._CBC.IV(ivBytes: initializationVector),
      noPadding: !removesPadding
    )
  }

  static func aesCBCEncrypt(
    _ plaintext: Data,
    key: Data,
    initializationVector: Data,
    addsPadding: Bool
  ) throws -> Data {
    try AES._CBC.encrypt(
      plaintext,
      using: SymmetricKey(data: key),
      iv: try AES._CBC.IV(ivBytes: initializationVector),
      noPadding: !addsPadding
    )
  }

  static func aesECBDecryptBlock(_ ciphertext: Data, key: Data) throws -> Data {
    guard ciphertext.count == 16 else {
      throw PDFParsingError.malformed(
        .init(offset: 0, message: "An AES-ECB operation requires one complete block.")
      )
    }
    return try aesCBCDecrypt(
      ciphertext,
      key: key,
      initializationVector: Data(repeating: 0, count: 16),
      removesPadding: false
    )
  }

  static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    var difference = lhs.count ^ rhs.count
    let count = max(lhs.count, rhs.count)
    for index in 0..<count {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      difference |= Int(left ^ right)
    }
    return difference == 0
  }
}
