import Foundation

/// Exchanges Grip can connect to. Only Hyperliquid for now; the account model is ready for more.
public enum ExchangeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hyperliquid
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .hyperliquid: return "Hyperliquid"
        }
    }
}

/// A connected exchange account. Holds only public information; the API-wallet key lives in the Keychain
/// under `keychainAccount`.
public struct ExchangeAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exchange: ExchangeKind
    public var network: HLNetwork
    public var label: String
    public var address: String            // main wallet (public)
    public var agentAddress: String?      // API wallet (public), nil = read-only
    public var agentName: String?
    public var agentValidUntil: Date?
    public var lastCheck: Date?
    public var lastCheckOK: Bool?
    public var createdAt: Date

    public init(id: UUID = UUID(), exchange: ExchangeKind = .hyperliquid, network: HLNetwork, label: String, address: String,
                agentAddress: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.exchange = exchange; self.network = network; self.label = label; self.address = address
        self.agentAddress = agentAddress; self.createdAt = createdAt
    }

    public var keychainAccount: String { "account-\(id.uuidString)" }
    public var canTrade: Bool { agentAddress != nil }
}

/// What the user pasted into a field.
public enum CredentialKind: Equatable, Sendable {
    case empty
    case address(String)       // 0x + 40 hex
    case privateKey            // 64 hex (with or without 0x)
    case invalid
}

public enum Credentials {
    public static func classify(_ raw: String) -> CredentialKind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .empty }
        let hex = s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard !hex.isEmpty, hex.allSatisfy({ $0.isHexDigit }) else { return .invalid }
        if hex.count == 64 { return .privateKey }
        if hex.count == 40 && s.lowercased().hasPrefix("0x") { return .address(EthSigner.checksum(s)) }
        return .invalid
    }

    /// "0x1234…cdef"
    public static func mask(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(4))
    }

    public static func same(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }
}

// MARK: - Hyperliquid account roles

public enum AddressRole: Equatable, Sendable {
    case user
    case agent(master: String)
    case vault
    case subAccount(master: String)
    case missing
    case unknown(String)
}

public struct AgentInfo: Equatable, Sendable {
    public var name: String
    public var address: String
    public var validUntil: Date?
}

/// The read-only calls the connection test needs (mockable in tests).
public protocol HLInfoAPI: Sendable {
    func userRole(_ address: String) async throws -> AddressRole
    func extraAgents(user: String) async throws -> [AgentInfo]
    func accountState(user: String) async throws -> AccountState
}

extension HLClient: HLInfoAPI {
    public func userRole(_ address: String) async throws -> AddressRole {
        let raw = try await info(["type": "userRole", "user": address])
        guard let obj = raw as? [String: Any], let role = obj["role"] as? String else { throw HLError.decoding("userRole") }
        let data = obj["data"] as? [String: Any]
        switch role {
        case "user": return .user
        case "agent": return .agent(master: data?["user"] as? String ?? "")
        case "vault": return .vault
        case "subAccount": return .subAccount(master: data?["master"] as? String ?? "")
        case "missing": return .missing
        default: return .unknown(role)
        }
    }

    public func extraAgents(user: String) async throws -> [AgentInfo] {
        let raw = try await info(["type": "extraAgents", "user": user])
        guard let arr = raw as? [[String: Any]] else { throw HLError.decoding("extraAgents") }
        return arr.compactMap { a in
            guard let addr = a["address"] as? String else { return nil }
            let until = (a["validUntil"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            return AgentInfo(name: a["name"] as? String ?? "", address: addr, validUntil: until)
        }
    }
}

// MARK: - Connection test

public struct CheckStep: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, running, ok, warning, failed, skipped }
    public var id: String
    public var title: String
    public var status: Status
    public var detail: String

    public init(id: String, title: String, status: Status = .pending, detail: String = "") {
        self.id = id; self.title = title; self.status = status; self.detail = detail
    }
}

public struct ConnectionReport: Equatable, Sendable {
    public var steps: [CheckStep]
    public var accountValue: Double?
    public var spotValue: Double?
    public var mode: AccountMode?
    public var positions: Int?
    public var agentAddress: String?
    public var agentName: String?
    public var agentValidUntil: Date?
    /// Set when the user entered an API-wallet address as main address: the real main address.
    public var suggestedAddress: String?
    /// The API wallet is approved, but on the other network.
    public var suggestedNetwork: HLNetwork?

    /// Usable: nothing failed.
    public var passed: Bool { !steps.contains { $0.status == .failed } && steps.contains { $0.status == .ok } }
    public var canTrade: Bool { passed && steps.first { $0.id == "agent" }?.status != .skipped }
}

public enum ConnectionTester {
    /// Runs all checks; `progress` is called after every step so the UI can show them one by one.
    public static func run(api: HLInfoAPI, otherNetworkAPI: HLInfoAPI? = nil, network: HLNetwork, address raw: String,
                           agentKey: String?, now: Date = Date(),
                           progress: (@Sendable ([CheckStep]) async -> Void)? = nil) async -> ConnectionReport {
        let net = network.isMainnet ? "Mainnet" : "Testnet"
        var report = ConnectionReport(steps: [
            CheckStep(id: "address", title: "Wallet-adres"),
            CheckStep(id: "connection", title: "Verbinding met Hyperliquid \(net)"),
            CheckStep(id: "account", title: "Account gevonden"),
            CheckStep(id: "key", title: "API-wallet sleutel"),
            CheckStep(id: "agent", title: "API-wallet goedgekeurd voor dit account"),
        ])
        func set(_ id: String, _ status: CheckStep.Status, _ detail: String = "") async {
            if let i = report.steps.firstIndex(where: { $0.id == id }) { report.steps[i].status = status; report.steps[i].detail = detail }
            await progress?(report.steps)
        }
        func skipRest(after id: String, _ why: String) async {
            guard let i = report.steps.firstIndex(where: { $0.id == id }) else { return }
            for j in (i + 1)..<report.steps.count where report.steps[j].status == .pending {
                report.steps[j].status = .skipped; report.steps[j].detail = why
            }
            await progress?(report.steps)
        }

        // 1. Address format
        let address: String
        switch Credentials.classify(raw) {
        case .address(let a):
            address = a
            await set("address", .ok, Credentials.mask(a))
        case .privateKey:
            await set("address", .failed, "Dit is een private key, geen adres. Vul hier het publieke adres van je hoofdwallet in (0x + 40 tekens).")
            await skipRest(after: "address", "Eerst een geldig adres invullen.")
            return report
        case .empty:
            await set("address", .failed, "Vul het adres van je hoofdwallet in.")
            await skipRest(after: "address", "Eerst een adres invullen.")
            return report
        case .invalid:
            await set("address", .failed, "Geen geldig adres. Een adres begint met 0x en heeft daarna 40 tekens.")
            await skipRest(after: "address", "Eerst een geldig adres invullen.")
            return report
        }

        // 2 + 3. Reach the API and look up the account
        await set("connection", .running)
        let role: AddressRole
        do {
            role = try await api.userRole(address)
            await set("connection", .ok, "api.hyperliquid\(network.isMainnet ? "" : "-testnet").xyz bereikbaar")
        } catch {
            await set("connection", .failed, "Kon Hyperliquid niet bereiken: \(error.localizedDescription)")
            await skipRest(after: "connection", "Geen verbinding.")
            return report
        }

        await set("account", .running)
        switch role {
        case .agent(let master):
            report.suggestedAddress = EthSigner.checksum(master)
            await set("account", .failed, "Dit is het adres van een API-wallet, niet van je hoofdaccount. Je hoofdadres is \(Credentials.mask(master)).")
            await skipRest(after: "account", "Gebruik eerst je hoofdadres.")
            return report
        case .vault:
            await set("account", .failed, "Dit is een vault-adres. Gebruik het adres van je eigen wallet.")
            await skipRest(after: "account", "Gebruik eerst je eigen adres.")
            return report
        case .subAccount:
            await set("account", .failed, "Subaccounts worden nog niet ondersteund. Gebruik het adres van je hoofdaccount.")
            await skipRest(after: "account", "Gebruik eerst je hoofdadres.")
            return report
        default:
            break
        }
        do {
            let state = try await api.accountState(user: address)
            report.accountValue = state.accountValue
            report.positions = state.positions.count
            report.accountValue = state.accountValue
            report.spotValue = state.spotValue
            report.mode = state.mode
            let total = state.mode.balancesOnSpot ? state.accountValue : state.accountValue + state.spotValue
            let posText = "\(state.positions.count) open positie\(state.positions.count == 1 ? "" : "s")"
            if total <= 0 && state.positions.isEmpty {
                await set("account", .warning, "\(state.mode.label), maar zonder saldo op \(net). Klopt het netwerk?")
            } else if !state.mode.balancesOnSpot && state.accountValue <= 0 && state.spotValue > 0 {
                await set("account", .warning, "\(state.mode.label) · \(posText). Je saldo staat op spot, niet op perps: zet USDC over naar perps (of zet Unified account aan) om te kunnen handelen.")
            } else {
                await set("account", .ok, "\(state.mode.label) · \(posText)")
            }
        } catch {
            await set("account", .failed, "Kon het account niet ophalen: \(error.localizedDescription)")
            await skipRest(after: "account", "Account niet gevonden.")
            return report
        }

        // 4. Key
        guard let key = agentKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            await set("key", .skipped, "Geen sleutel: alleen-lezen (saldo, posities, historie). Handelen kan niet.")
            await set("agent", .skipped, "Alleen-lezen.")
            return report
        }
        let signer: EthSigner
        do {
            signer = try EthSigner(privateKeyHex: key)
            report.agentAddress = signer.address
        } catch {
            await set("key", .failed, "Ongeldige sleutel. Plak de private key van je API-wallet (64 tekens, eventueel met 0x).")
            await set("agent", .skipped, "")
            return report
        }
        if Credentials.same(signer.address, address) {
            await set("key", .failed, "Dit is de sleutel van je hoofdwallet. Gebruik die nooit in een app: maak een API-wallet aan (More → API).")
            await set("agent", .skipped, "")
            return report
        }
        await set("key", .ok, "Hoort bij API-wallet \(Credentials.mask(signer.address)) · bewaard in sleutelhanger")

        // 5. Is the API wallet approved for this account on this network?
        await set("agent", .running)
        do {
            let agentRole = try await api.userRole(signer.address)
            if case .agent(let master) = agentRole, Credentials.same(master, address) {
                let info = try? await api.extraAgents(user: address).first { Credentials.same($0.address, signer.address) }
                report.agentName = info?.name
                report.agentValidUntil = info?.validUntil
                var detail = info.map { $0.name.isEmpty ? "Goedgekeurd" : "Goedgekeurd als “\($0.name)”" } ?? "Goedgekeurd"
                if let until = info?.validUntil {
                    let days = Int(until.timeIntervalSince(now) / 86400)
                    if days < 0 {
                        await set("agent", .failed, "Deze API-wallet is verlopen. Maak een nieuwe aan op Hyperliquid.")
                        return report
                    }
                    detail += " · nog \(days) dagen geldig"
                    if days < 14 {
                        await set("agent", .warning, detail + ". Verleng hem binnenkort op Hyperliquid.")
                        return report
                    }
                }
                await set("agent", .ok, detail)
            } else if case .agent(let master) = agentRole {
                await set("agent", .failed, "Deze API-wallet hoort bij een ander account (\(Credentials.mask(master))).")
            } else {
                // Maybe approved on the other network?
                if let other = otherNetworkAPI, case .agent(let m)? = try? await other.userRole(signer.address), Credentials.same(m, address) {
                    report.suggestedNetwork = network.isMainnet ? .testnet : .mainnet
                    await set("agent", .failed, "Deze API-wallet is goedgekeurd op \(network.isMainnet ? "Testnet" : "Mainnet"), niet op \(net). Kies het andere netwerk.")
                } else {
                    await set("agent", .failed, "Nog niet goedgekeurd op \(net). Maak hem aan via More → API op Hyperliquid en klik op Authorize.")
                }
            }
        } catch {
            await set("agent", .failed, "Kon de goedkeuring niet controleren: \(error.localizedDescription)")
        }
        return report
    }
}
