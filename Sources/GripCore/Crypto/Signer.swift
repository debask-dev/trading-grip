import Foundation
import libsecp256k1

public enum SignerError: Error, LocalizedError {
    case invalidPrivateKey
    case signingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: return "Ongeldige private key (verwacht 64 hex-tekens)."
        case .signingFailed: return "Ondertekenen mislukt."
        }
    }
}

public struct EthSignature: Equatable, Sendable {
    public let r: Data
    public let s: Data
    public let v: Int

    public var wire: WireValue {
        .map([("r", .string("0x" + r.hex)), ("s", .string("0x" + s.hex)), ("v", .int(Int64(v)))])
    }
}

/// secp256k1 signer for an Ethereum-style private key (the Hyperliquid API wallet key).
public final class EthSigner: @unchecked Sendable {
    private let secret: [UInt8]
    public let address: String

    public init(privateKeyHex: String) throws {
        let trimmed = privateKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = Data(hex: trimmed), key.count == 32 else { throw SignerError.invalidPrivateKey }
        secret = [UInt8](key)
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_NONE)) else { throw SignerError.signingFailed }
        defer { secp256k1_context_destroy(ctx) }
        guard secp256k1_ec_seckey_verify(ctx, secret) == 1 else { throw SignerError.invalidPrivateKey }

        var pubkey = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_create(ctx, &pubkey, secret) == 1 else { throw SignerError.invalidPrivateKey }
        var out = [UInt8](repeating: 0, count: 65)
        var len = 65
        secp256k1_ec_pubkey_serialize(ctx, &out, &len, &pubkey, UInt32(SECP256K1_EC_UNCOMPRESSED))
        let hash = Keccak.hash256(Array(out[1..<65]))
        address = EthSigner.checksum("0x" + Data(hash.suffix(20)).hex)
    }

    /// Signs a 32-byte digest. v is 27 or 28.
    public func sign(digest: Data) throws -> EthSignature {
        guard digest.count == 32 else { throw SignerError.signingFailed }
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_NONE)) else { throw SignerError.signingFailed }
        defer { secp256k1_context_destroy(ctx) }
        var sig = secp256k1_ecdsa_recoverable_signature()
        let msg = [UInt8](digest)
        guard secp256k1_ecdsa_sign_recoverable(ctx, &sig, msg, secret, nil, nil) == 1 else { throw SignerError.signingFailed }
        var compact = [UInt8](repeating: 0, count: 64)
        var recid: Int32 = 0
        secp256k1_ecdsa_recoverable_signature_serialize_compact(ctx, &compact, &recid, &sig)
        return EthSignature(r: Data(compact[0..<32]), s: Data(compact[32..<64]), v: Int(recid) + 27)
    }

    /// EIP-55 checksum casing.
    public static func checksum(_ address: String) -> String {
        var hex = address.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        let hash = Keccak.hash256(Array(hex.utf8)).hex
        var result = "0x"
        for (c, h) in zip(hex, hash) {
            if c.isLetter, let v = Int(String(h), radix: 16), v >= 8 { result.append(c.uppercased()) } else { result.append(c) }
        }
        return result
    }

    public static func isValidAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return Data(hex: t) != nil
    }
}

/// Hyperliquid L1 action signing (phantom agent, EIP-712).
public enum HLSigning {
    static func uint256(_ v: UInt64) -> Data {
        var d = Data(repeating: 0, count: 24)
        for i in stride(from: 7, through: 0, by: -1) { d.append(UInt8((v >> UInt64(8 * i)) & 0xFF)) }
        return d
    }

    static let domainSeparator: Data = {
        let typeHash = Keccak.hash256(Array("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8))
        var d = Data()
        d.append(typeHash)
        d.append(Keccak.hash256(Array("Exchange".utf8)))
        d.append(Keccak.hash256(Array("1".utf8)))
        d.append(uint256(1337))
        d.append(Data(repeating: 0, count: 32))
        return Keccak.hash256(d)
    }()

    /// keccak(msgpack(action) || nonce(8, BE) || vaultFlag [|| vault])
    public static func actionHash(action: WireValue, nonce: UInt64, vaultAddress: String? = nil) -> Data {
        var data = action.msgpack()
        for i in stride(from: 7, through: 0, by: -1) { data.append(UInt8((nonce >> UInt64(8 * i)) & 0xFF)) }
        if let vault = vaultAddress, let bytes = Data(hex: vault) {
            data.append(0x01)
            data.append(bytes)
        } else {
            data.append(0x00)
        }
        return Keccak.hash256(data)
    }

    public static func agentDigest(connectionId: Data, isMainnet: Bool) -> Data {
        let typeHash = Keccak.hash256(Array("Agent(string source,bytes32 connectionId)".utf8))
        var s = Data()
        s.append(typeHash)
        s.append(Keccak.hash256(Array((isMainnet ? "a" : "b").utf8)))
        s.append(connectionId)
        let structHash = Keccak.hash256(s)
        var msg = Data([0x19, 0x01])
        msg.append(domainSeparator)
        msg.append(structHash)
        return Keccak.hash256(msg)
    }

    public static func signL1Action(_ action: WireValue, nonce: UInt64, isMainnet: Bool, signer: EthSigner) throws -> EthSignature {
        let hash = actionHash(action: action, nonce: nonce)
        return try signer.sign(digest: agentDigest(connectionId: hash, isMainnet: isMainnet))
    }
}
