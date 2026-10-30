// Ed25519 keys and signatures for DayPatch's self-updates.
//
//   swift tools/update-key.swift generate <private-key-file>   writes the private key (base64, mode 600), prints the public key
//   swift tools/update-key.swift sign <file>                    prints the base64 signature; key from $DAYPATCH_UPDATE_PRIVATE_KEY
//   swift tools/update-key.swift verify <file> <sig-file> <public-key-base64>
import CryptoKit
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "generate":
    guard args.count == 2 else { fail("usage: generate <private-key-file>") }
    let path = args[args.startIndex + 1]
    if FileManager.default.fileExists(atPath: path) { fail("\(path) already exists; not overwriting a signing key") }
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: path, contents: key.rawRepresentation.base64EncodedData(), attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 2 else { fail("usage: sign <file>") }
    guard let b64 = ProcessInfo.processInfo.environment["DAYPATCH_UPDATE_PRIVATE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          let raw = Data(base64Encoded: b64), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("DAYPATCH_UPDATE_PRIVATE_KEY is missing or invalid")
    }
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[args.startIndex + 1]), options: .mappedIfSafe)
    print(try! key.signature(for: data).base64EncodedString())
case "verify":
    guard args.count == 4 else { fail("usage: verify <file> <sig-file> <public-key-base64>") }
    let a = Array(args)
    let data = try! Data(contentsOf: URL(fileURLWithPath: a[1]), options: .mappedIfSafe)
    let sig = Data(base64Encoded: try! String(contentsOfFile: a[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    let key = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: a[3])!)
    if key.isValidSignature(sig, for: data) { print("OK") } else { fail("signature does not match") }
default:
    fail("usage: update-key.swift generate <file> | sign <file> | verify <file> <sig-file> <public-key>")
}
