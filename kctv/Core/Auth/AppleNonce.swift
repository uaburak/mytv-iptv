import CryptoKit
import Foundation

/// Firebase, Apple girişinde replay saldırısına karşı ham nonce'un SHA256'sını
/// Apple'a, ham hâlini kendisine göndermemizi bekler.
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            // 252 ve üstünü atarak modulo sapmasını engelliyoruz (256 % 64 == 0).
            if byte < 252 {
                result.append(charset[Int(byte) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
