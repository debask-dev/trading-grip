import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HLNetwork: String, CaseIterable, Codable, Identifiable, Sendable {
    case testnet, mainnet
    public var id: String { rawValue }
    public var label: String { self == .mainnet ? "Mainnet (echt geld)" : "Testnet" }
    public var isMainnet: Bool { self == .mainnet }
    public var apiURL: URL { URL(string: isMainnet ? "https://api.hyperliquid.xyz" : "https://api.hyperliquid-testnet.xyz")! }
    public var wsURL: URL { URL(string: isMainnet ? "wss://api.hyperliquid.xyz/ws" : "wss://api.hyperliquid-testnet.xyz/ws")! }
}

public enum HLError: Error, LocalizedError, Equatable {
    case http(Int, String)
    case decoding(String)
    case exchange(String)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "Hyperliquid gaf HTTP \(code): \(body.prefix(200))"
        case .decoding(let what): return "Onverwacht antwoord van Hyperliquid (\(what))."
        case .exchange(let msg): return msg
        case .notConfigured: return "Stel eerst je wallet-adres en API-wallet in (Instellingen)."
        }
    }
}

// MARK: - Order building

public enum OrderKind: Equatable, Sendable {
    case limit(tif: String)                       // "Gtc", "Ioc", "Alo"
    case trigger(triggerPx: Double, isMarket: Bool, tpsl: TpSl)
}

public struct OrderRequest: Equatable, Sendable {
    public var asset: AssetInfo
    public var isBuy: Bool
    public var size: Double
    public var limitPx: Double
    public var reduceOnly: Bool
    public var kind: OrderKind

    public init(asset: AssetInfo, isBuy: Bool, size: Double, limitPx: Double, reduceOnly: Bool, kind: OrderKind) {
        self.asset = asset; self.isBuy = isBuy; self.size = size; self.limitPx = limitPx; self.reduceOnly = reduceOnly; self.kind = kind
    }

    public var wire: WireValue {
        let type: WireValue
        switch kind {
        case .limit(let tif):
            type = .map([("limit", .map([("tif", .string(tif))]))])
        case .trigger(let px, let isMarket, let tpsl):
            type = .map([("trigger", .map([
                ("isMarket", .bool(isMarket)),
                ("triggerPx", .string(HLFormat.wire(HLFormat.roundPrice(px, szDecimals: asset.szDecimals)))),
                ("tpsl", .string(tpsl.rawValue)),
            ]))])
        }
        return .map([
            ("a", .int(Int64(asset.index))),
            ("b", .bool(isBuy)),
            ("p", .string(HLFormat.wire(HLFormat.roundPrice(limitPx, szDecimals: asset.szDecimals)))),
            ("s", .string(HLFormat.wire(HLFormat.roundSize(size, szDecimals: asset.szDecimals)))),
            ("r", .bool(reduceOnly)),
            ("t", type),
        ])
    }
}

public enum HLActions {
    public static func order(_ orders: [OrderRequest], grouping: String = "na") -> WireValue {
        .map([("type", .string("order")), ("orders", .array(orders.map { $0.wire })), ("grouping", .string(grouping))])
    }

    public static func modify(oid: Int64, order: OrderRequest) -> WireValue {
        .map([("type", .string("batchModify")), ("modifies", .array([.map([("oid", .int(oid)), ("order", order.wire)])]))])
    }

    public static func cancel(asset: Int, oid: Int64) -> WireValue {
        .map([("type", .string("cancel")), ("cancels", .array([.map([("a", .int(Int64(asset))), ("o", .int(oid))])]))])
    }

    public static func updateLeverage(asset: Int, isCross: Bool, leverage: Int) -> WireValue {
        .map([("type", .string("updateLeverage")), ("asset", .int(Int64(asset))), ("isCross", .bool(isCross)), ("leverage", .int(Int64(leverage)))])
    }
}

public enum OrderStatus: Equatable, Sendable {
    case resting(oid: Int64)
    case filled(oid: Int64, size: Double, avgPx: Double)
    case error(String)
    case success
}

// MARK: - Client

public final class HLClient: @unchecked Sendable {
    public let network: HLNetwork
    private let session: URLSession
    private let nonceLock = NSLock()
    private var lastNonce: UInt64 = 0

    public init(network: HLNetwork, session: URLSession = .shared) {
        self.network = network
        self.session = session
    }

    // MARK: Raw

    private func post(_ path: String, body: Data) async throws -> Any {
        var req = URLRequest(url: network.apiURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 20
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HLError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public func info(_ payload: [String: Any]) async throws -> Any {
        try await post("info", body: try JSONSerialization.data(withJSONObject: payload))
    }

    // MARK: Market data

    public func meta() async throws -> (assets: [AssetInfo], contexts: [String: AssetContext]) {
        let raw = try await info(["type": "metaAndAssetCtxs"])
        guard let arr = raw as? [Any], arr.count >= 2,
              let meta = arr[0] as? [String: Any], let universe = meta["universe"] as? [[String: Any]],
              let ctxs = arr[1] as? [[String: Any]] else { throw HLError.decoding("meta") }
        var assets: [AssetInfo] = []
        var contexts: [String: AssetContext] = [:]
        for (i, u) in universe.enumerated() {
            guard let name = u["name"] as? String else { continue }
            if (u["isDelisted"] as? Bool) == true { continue }
            assets.append(AssetInfo(name: name, index: i, szDecimals: u["szDecimals"] as? Int ?? 2,
                                    maxLeverage: u["maxLeverage"] as? Int ?? 10, onlyIsolated: u["onlyIsolated"] as? Bool ?? false))
            if i < ctxs.count {
                let c = ctxs[i]
                contexts[name] = AssetContext(markPx: d(c["markPx"]), prevDayPx: d(c["prevDayPx"]), funding: d(c["funding"]), dayVolume: d(c["dayNtlVlm"]))
            }
        }
        return (assets, contexts)
    }

    public func candles(coin: String, timeframe: Timeframe, count: Int? = nil, endTime: Int64? = nil) async throws -> [Candle] {
        let end = endTime ?? Int64(Date().timeIntervalSince1970 * 1000)
        let start = end - timeframe.milliseconds * Int64(count ?? timeframe.historyCount)
        let raw = try await info(["type": "candleSnapshot", "req": ["coin": coin, "interval": timeframe.rawValue, "startTime": start, "endTime": end]])
        guard let arr = raw as? [[String: Any]] else { throw HLError.decoding("candles") }
        return arr.compactMap(Self.parseCandle).sorted { $0.time < $1.time }
    }

    public static func parseCandle(_ c: [String: Any]) -> Candle? {
        guard let t = (c["t"] as? NSNumber)?.int64Value else { return nil }
        return Candle(time: t, open: d(c["o"]), high: d(c["h"]), low: d(c["l"]), close: d(c["c"]), volume: d(c["v"]))
    }

    // MARK: Account

    public func accountState(user: String) async throws -> AccountState {
        async let perpsState = perpsAccountState(user: user)
        async let modeRaw = try? info(["type": "userAbstraction", "user": user])
        async let spotRaw = try? info(["type": "spotClearinghouseState", "user": user])
        let (perps, m, spot) = try await (perpsState, modeRaw, spotRaw)
        let mode = AccountMode(api: m as? String ?? "disabled")
        let balances = await spotBalances(from: spot)
        return AccountState.combine(perps: perps, mode: mode, spot: balances)
    }

    /// Spot balances valued in USD (stablecoins at 1, other tokens at their USDC spot price).
    func spotBalances(from raw: Any?) async -> [SpotBalance] {
        guard let obj = raw as? [String: Any], let arr = obj["balances"] as? [[String: Any]] else { return [] }
        let stable: Set<String> = ["USDC", "USDT", "USDT0", "USDH", "USDE", "USDHL"]
        var balances = arr.compactMap { b -> SpotBalance? in
            guard let coin = b["coin"] as? String else { return nil }
            let total = d(b["total"])
            return SpotBalance(coin: coin, token: (b["token"] as? NSNumber)?.intValue ?? -1, total: total, hold: d(b["hold"]),
                               usdValue: stable.contains(coin.uppercased()) ? total : 0)
        }
        if balances.contains(where: { !stable.contains($0.coin.uppercased()) && $0.total != 0 }), let prices = try? await spotPrices() {
            for i in balances.indices where !stable.contains(balances[i].coin.uppercased()) {
                balances[i].usdValue = balances[i].total * (prices[balances[i].token] ?? 0)
            }
        }
        return balances
    }

    /// USDC price per spot token index, from the token/USDC pairs.
    func spotPrices() async throws -> [Int: Double] {
        let raw = try await info(["type": "spotMetaAndAssetCtxs"])
        guard let arr = raw as? [Any], arr.count >= 2, let meta = arr[0] as? [String: Any],
              let universe = meta["universe"] as? [[String: Any]], let ctxs = arr[1] as? [[String: Any]] else { throw HLError.decoding("spotMeta") }
        var byCoin: [String: Double] = [:]
        for c in ctxs {
            guard let coin = c["coin"] as? String else { continue }
            let mid = d(c["midPx"]), mark = d(c["markPx"])
            byCoin[coin] = mid > 0 ? mid : mark
        }
        var out: [Int: Double] = [0: 1]
        for u in universe {
            guard let tokens = u["tokens"] as? [Int], tokens.count == 2, tokens[1] == 0, let name = u["name"] as? String,
                  let px = byCoin[name], out[tokens[0]] == nil else { continue }
            out[tokens[0]] = px
        }
        return out
    }

    private func perpsAccountState(user: String) async throws -> AccountState {
        async let chRaw = info(["type": "clearinghouseState", "user": user])
        async let ordRaw = info(["type": "frontendOpenOrders", "user": user])
        let (ch, ord) = try await (chRaw, ordRaw)
        guard let state = ch as? [String: Any] else { throw HLError.decoding("clearinghouseState") }
        let summary = state["marginSummary"] as? [String: Any] ?? [:]
        var positions: [Position] = []
        for ap in state["assetPositions"] as? [[String: Any]] ?? [] {
            guard let p = ap["position"] as? [String: Any], let coin = p["coin"] as? String else { continue }
            let size = d(p["szi"])
            if size == 0 { continue }
            let lev = p["leverage"] as? [String: Any] ?? [:]
            let liq = p["liquidationPx"].flatMap { $0 is NSNull ? nil : d($0) }
            positions.append(Position(coin: coin, size: size, entryPx: d(p["entryPx"]), unrealizedPnl: d(p["unrealizedPnl"]),
                                      liquidationPx: liq, leverage: (lev["value"] as? NSNumber)?.intValue ?? 1,
                                      isCross: (lev["type"] as? String) != "isolated", marginUsed: d(p["marginUsed"])))
        }
        let orders: [OpenOrder] = (ord as? [[String: Any]] ?? []).compactMap(Self.parseOrder)
        return AccountState(accountValue: d(summary["accountValue"]), withdrawable: d(state["withdrawable"]),
                            marginUsed: d(summary["totalMarginUsed"]), positions: positions, openOrders: orders)
    }

    static func parseOrder(_ o: [String: Any]) -> OpenOrder? {
        guard let coin = o["coin"] as? String, let oid = (o["oid"] as? NSNumber)?.int64Value else { return nil }
        let type = o["orderType"] as? String ?? "Limit"
        let isTrigger = o["isTrigger"] as? Bool ?? false
        var tpsl: TpSl? = nil
        if isTrigger { tpsl = type.lowercased().contains("take profit") ? .tp : .sl }
        let trig = d(o["triggerPx"])
        return OpenOrder(oid: oid, coin: coin, isBuy: (o["side"] as? String) == "B", limitPx: d(o["limitPx"]), size: d(o["sz"]),
                         reduceOnly: o["reduceOnly"] as? Bool ?? false, isTrigger: isTrigger, triggerPx: trig > 0 ? trig : nil,
                         tpsl: tpsl, isPositionTpsl: o["isPositionTpsl"] as? Bool ?? false, orderType: type,
                         timestamp: (o["timestamp"] as? NSNumber)?.int64Value ?? 0)
    }

    public func fills(user: String, since: Int64? = nil) async throws -> [Fill] {
        let raw: Any
        if let since { raw = try await info(["type": "userFillsByTime", "user": user, "startTime": since, "aggregateByTime": true]) }
        else { raw = try await info(["type": "userFills", "user": user, "aggregateByTime": true]) }
        guard let arr = raw as? [[String: Any]] else { throw HLError.decoding("fills") }
        return arr.compactMap { f in
            guard let coin = f["coin"] as? String, let time = (f["time"] as? NSNumber)?.int64Value else { return nil }
            return Fill(coin: coin, px: d(f["px"]), sz: d(f["sz"]), isBuy: (f["side"] as? String) == "B", time: time,
                        startPosition: d(f["startPosition"]), dir: f["dir"] as? String ?? "", closedPnl: d(f["closedPnl"]),
                        fee: d(f["fee"]), oid: (f["oid"] as? NSNumber)?.int64Value ?? 0, tid: (f["tid"] as? NSNumber)?.int64Value ?? time)
        }
    }

    /// The user's own fee rates (volume tier, staking and referral discounts included).
    public func feeRates(user: String) async throws -> FeeRates {
        let raw = try await info(["type": "userFees", "user": user])
        guard let obj = raw as? [String: Any] else { throw HLError.decoding("userFees") }
        let taker = d(obj["userCrossRate"]), maker = d(obj["userAddRate"])
        return taker > 0 ? FeeRates(taker: taker, maker: maker) : .base
    }

    /// Funding payments since `since` (paged, at most 10 pages of 500).
    public func funding(user: String, since: Int64) async throws -> [FundingPayment] {
        var out: [FundingPayment] = []
        var start = since
        for _ in 0..<10 {
            let raw = try await info(["type": "userFunding", "user": user, "startTime": start])
            guard let arr = raw as? [[String: Any]] else { throw HLError.decoding("userFunding") }
            let page: [FundingPayment] = arr.compactMap { e in
                guard let t = (e["time"] as? NSNumber)?.int64Value, let delta = e["delta"] as? [String: Any],
                      let coin = delta["coin"] as? String else { return nil }
                return FundingPayment(time: t, coin: coin, usdc: d(delta["usdc"]))
            }
            out += page
            guard arr.count >= 500, let last = page.map({ $0.time }).max() else { break }
            start = last + 1
        }
        return out
    }

    /// Order types of the user's recent orders (up to 2000), to label fills as TP / SL / close.
    public func orderKinds(user: String) async throws -> [Int64: OrderKindTag] {
        let raw = try await info(["type": "historicalOrders", "user": user])
        guard let arr = raw as? [[String: Any]] else { throw HLError.decoding("historicalOrders") }
        var out: [Int64: OrderKindTag] = [:]
        for e in arr {
            guard let o = e["order"] as? [String: Any], let oid = (o["oid"] as? NSNumber)?.int64Value else { continue }
            out[oid] = OrderKindTag.from(orderType: o["orderType"] as? String ?? "Limit", reduceOnly: o["reduceOnly"] as? Bool ?? false, tif: o["tif"] as? String)
        }
        return out
    }

    public func portfolio(user: String) async throws -> [PortfolioPeriod: PortfolioSeries] {
        let raw = try await info(["type": "portfolio", "user": user])
        guard let arr = raw as? [[Any]] else { throw HLError.decoding("portfolio") }
        var out: [PortfolioPeriod: PortfolioSeries] = [:]
        for entry in arr {
            guard entry.count == 2, let key = entry[0] as? String, let period = PortfolioPeriod(rawValue: key),
                  let body = entry[1] as? [String: Any] else { continue }
            func series(_ k: String) -> [PortfolioSeries.Point] {
                (body[k] as? [[Any]] ?? []).compactMap { p in
                    guard p.count == 2, let t = (p[0] as? NSNumber)?.doubleValue else { return nil }
                    return PortfolioSeries.Point(time: Date(timeIntervalSince1970: t / 1000), value: d(p[1]))
                }
            }
            out[period] = PortfolioSeries(accountValue: series("accountValueHistory"), pnl: series("pnlHistory"))
        }
        return out
    }

    // MARK: Exchange

    private func nextNonce() -> UInt64 {
        nonceLock.lock(); defer { nonceLock.unlock() }
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        lastNonce = max(now, lastNonce + 1)
        return lastNonce
    }

    @discardableResult
    public func exchange(_ action: WireValue, signer: EthSigner) async throws -> [OrderStatus] {
        let nonce = nextNonce()
        let sig = try HLSigning.signL1Action(action, nonce: nonce, isMainnet: network.isMainnet, signer: signer)
        let body = WireValue.map([("action", action), ("nonce", .int(Int64(nonce))), ("signature", sig.wire), ("vaultAddress", .null)]).json()
        let raw = try await post("exchange", body: Data(body.utf8))
        return try Self.parseExchangeResponse(raw)
    }

    static func parseExchangeResponse(_ raw: Any) throws -> [OrderStatus] {
        guard let obj = raw as? [String: Any] else { throw HLError.decoding("exchange") }
        if (obj["status"] as? String) != "ok" {
            throw HLError.exchange(Self.translate(obj["response"] as? String ?? "Onbekende fout"))
        }
        let resp = obj["response"] as? [String: Any]
        let data = resp?["data"] as? [String: Any]
        guard let statuses = data?["statuses"] as? [Any] else { return [.success] }
        let parsed: [OrderStatus] = statuses.map { s in
            if let str = s as? String { return str == "success" ? .success : .error(str) }
            guard let m = s as? [String: Any] else { return .error("?") }
            if let r = m["resting"] as? [String: Any] { return .resting(oid: (r["oid"] as? NSNumber)?.int64Value ?? 0) }
            if let f = m["filled"] as? [String: Any] {
                return .filled(oid: (f["oid"] as? NSNumber)?.int64Value ?? 0, size: d(f["totalSz"]), avgPx: d(f["avgPx"]))
            }
            if let e = m["error"] as? String { return .error(Self.translate(e)) }
            return .success
        }
        if let first = parsed.first, case .error(let msg) = first { throw HLError.exchange(msg) }
        return parsed
    }

    static func translate(_ msg: String) -> String {
        let m = msg.lowercased()
        if m.contains("insufficient margin") { return "Onvoldoende marge voor deze order." }
        if m.contains("does not exist") && m.contains("user") { return "Deze API-wallet is niet gekoppeld aan je account (of verkeerd netwerk gekozen)." }
        if m.contains("minimum value") { return "Order te klein: minimaal $10." }
        if m.contains("reduce only") { return "Reduce-only order zou je positie vergroten." }
        if m.contains("could not immediately match") { return "Geen directe match (te weinig liquiditeit binnen slippage)." }
        return msg
    }
}

/// Lenient number parsing: Hyperliquid sends most numbers as strings.
@inline(__always) func d(_ any: Any?) -> Double {
    if let s = any as? String { return Double(s) ?? 0 }
    if let n = any as? NSNumber { return n.doubleValue }
    return 0
}
