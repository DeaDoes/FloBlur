import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("usage: swift Tools/verify-update.swift <archive> <base64-signature> <app-info.plist>")
}
let arguments = CommandLine.arguments
do {
    let plist = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
    guard let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
          let publicKey = info["SUPublicEDKey"] as? String,
          let keyBytes = Data(base64Encoded: publicKey),
          let signature = Data(base64Encoded: arguments[2]) else {
        fail("invalid Sparkle public key or update signature")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        fail("update signature does not match the archive and FloBlur’s public key")
    }
    print("Verified Sparkle Ed25519 signature against FloBlur’s public key.")
} catch {
    fail(error.localizedDescription)
}
