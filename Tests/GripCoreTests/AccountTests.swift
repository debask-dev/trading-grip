import XCTest
@testable import GripCore

final class FakeInfo: HLInfoAPI, @unchecked Sendable {
    var roles: [String: AddressRole] = [:]
    var agents: [String: [AgentInfo]] = [:]
    var states: [String: AccountState] = [:]
    var failing = false

    func userRole(_ address: String) async throws -> AddressRole {
        if failing { throw HLError.http(500, "down") }
        return roles[address.lowercased()] ?? .user
    }
    func extraAgents(user: String) async throws -> [AgentInfo] { agents[user.lowercased()] ?? [] }
    func accountState(user: String) async throws -> AccountState { states[user.lowercased()] ?? .empty }
}

final class AccountTests: XCTestCase {
    let main = "0x14791697260E4c9A71f18484C9f997B308e59325"
    // Throwaway test key (also used in SigningTests); its address is `main` above.
    let mainKey = "0x0123456789012345678901234567890123456789012345678901234567890123"
    let agentKey = "0x1111111111111111111111111111111111111111111111111111111111111111"
    lazy var agentAddr = (try! EthSigner(privateKeyHex: agentKey)).address
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func funded() -> AccountState {
        AccountState(accountValue: 1234, withdrawable: 1000, marginUsed: 0, positions: [], openOrders: [])
    }

    func status(_ r: ConnectionReport, _ id: String) -> CheckStep.Status? { r.steps.first { $0.id == id }?.status }

    func testClassify() {
        XCTAssertEqual(Credentials.classify(""), .empty)
        XCTAssertEqual(Credentials.classify(" 0x14791697260e4c9a71f18484c9f997b308e59325 "), .address(main))
        XCTAssertEqual(Credentials.classify(mainKey), .privateKey)
        XCTAssertEqual(Credentials.classify(String(mainKey.dropFirst(2))), .privateKey)
        XCTAssertEqual(Credentials.classify("hello"), .invalid)
        XCTAssertEqual(Credentials.mask(main), "0x1479…9325")
    }

    func testHappyPath() async {
        let api = FakeInfo()
        api.states[main.lowercased()] = funded()
        api.roles[agentAddr.lowercased()] = .agent(master: main.lowercased())
        api.agents[main.lowercased()] = [AgentInfo(name: "Grip", address: agentAddr.lowercased(), validUntil: now.addingTimeInterval(90 * 86400))]
        let r = await ConnectionTester.run(api: api, network: .testnet, address: main, agentKey: agentKey, now: now)
        XCTAssertTrue(r.steps.allSatisfy { $0.status == .ok }, "\(r.steps)")
        XCTAssertTrue(r.passed && r.canTrade)
        XCTAssertEqual(r.agentName, "Grip")
        XCTAssertEqual(r.accountValue, 1234)
    }

    func testReadOnly() async {
        let api = FakeInfo()
        api.states[main.lowercased()] = funded()
        let r = await ConnectionTester.run(api: api, network: .mainnet, address: main, agentKey: nil, now: now)
        XCTAssertTrue(r.passed)
        XCTAssertFalse(r.canTrade)
        XCTAssertEqual(status(r, "key"), .skipped)
    }

    func testPrivateKeyInAddressFieldIsRejected() async {
        let r = await ConnectionTester.run(api: FakeInfo(), network: .testnet, address: agentKey, agentKey: nil, now: now)
        XCTAssertEqual(status(r, "address"), .failed)
        XCTAssertFalse(r.passed)
        XCTAssertTrue(r.steps.dropFirst().allSatisfy { $0.status == .skipped })
    }

    func testAgentAddressUsedAsMainAddress() async {
        let api = FakeInfo()
        api.roles[agentAddr.lowercased()] = .agent(master: main.lowercased())
        let r = await ConnectionTester.run(api: api, network: .testnet, address: agentAddr, agentKey: nil, now: now)
        XCTAssertEqual(status(r, "account"), .failed)
        XCTAssertEqual(r.suggestedAddress, main)
    }

    func testMainWalletKeyIsRefused() async {
        let api = FakeInfo()
        api.states[main.lowercased()] = funded()
        let r = await ConnectionTester.run(api: api, network: .testnet, address: main, agentKey: mainKey, now: now)
        XCTAssertEqual(status(r, "key"), .failed)
    }

    func testApprovedOnOtherNetwork() async {
        let api = FakeInfo(), other = FakeInfo()
        api.states[main.lowercased()] = funded()
        other.roles[agentAddr.lowercased()] = .agent(master: main.lowercased())
        let r = await ConnectionTester.run(api: api, otherNetworkAPI: other, network: .testnet, address: main, agentKey: agentKey, now: now)
        XCTAssertEqual(status(r, "agent"), .failed)
        XCTAssertEqual(r.suggestedNetwork, .mainnet)
    }

    func testExpiringAndEmptyAccountWarnings() async {
        let api = FakeInfo()
        api.roles[agentAddr.lowercased()] = .agent(master: main.lowercased())
        api.agents[main.lowercased()] = [AgentInfo(name: "", address: agentAddr, validUntil: now.addingTimeInterval(3 * 86400))]
        let r = await ConnectionTester.run(api: api, network: .testnet, address: main, agentKey: agentKey, now: now)
        XCTAssertEqual(status(r, "account"), .warning)     // no balance
        XCTAssertEqual(status(r, "agent"), .warning)       // expires in 3 days
        XCTAssertTrue(r.passed)
    }

    func testOffline() async {
        let api = FakeInfo()
        api.failing = true
        let r = await ConnectionTester.run(api: api, network: .testnet, address: main, agentKey: agentKey, now: now)
        XCTAssertEqual(status(r, "connection"), .failed)
        XCTAssertFalse(r.passed)
    }

    func testAccountCodable() throws {
        var a = ExchangeAccount(network: .testnet, label: "Test", address: main, agentAddress: agentAddr)
        a.lastCheckOK = true
        let back = try JSONDecoder().decode(ExchangeAccount.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back, a)
        XCTAssertTrue(back.keychainAccount.hasPrefix("account-"))
    }
}
