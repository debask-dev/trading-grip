#if os(macOS)
import SwiftUI
import AppKit
import GripCore

enum MainTab: String, CaseIterable, Identifiable {
    case trade, history, portfolio
    var id: String { rawValue }
    var label: String {
        switch self {
        case .trade: return "Traden"
        case .history: return "Historie"
        case .portfolio: return "Portfolio"
        }
    }
}

enum ChartTool: Equatable { case cursor, trendline }

/// The order being prepared on the chart before it is sent.
struct Ticket: Equatable {
    var entry: Double
    var stopLoss: Double
    var takeProfit: Double?
    var isMarket: Bool
}

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    var text: String
    var kind: Kind
}

enum LineID: Hashable {
    case ticketEntry, ticketSL, ticketTP, order(Int64), position
}

struct ChartLine: Identifiable, Equatable {
    var id: LineID
    var price: Double
    var color: NSColor
    var dashed: Bool
    var draggable: Bool
    var emphasized: Bool = false
}

@MainActor
final class AppState: ObservableObject {
    private let defaults = UserDefaults.standard
    private let store = JSONStore()

    // MARK: Settings
    @Published var network: HLNetwork {
        didSet {
            guard oldValue != network else { return }
            defaults.set(network.rawValue, forKey: "network")
            networkChanged()
        }
    }
    @Published var accountAddress: String {
        didSet {
            let trimmed = accountAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: "accountAddress")
            if oldValue.lowercased() != trimmed.lowercased() { accountChanged() }
        }
    }
    @Published var riskPercent: Double { didSet { defaults.set(riskPercent, forKey: "riskPercent") } }
    @Published var slippagePercent: Double { didSet { defaults.set(slippagePercent, forKey: "slippagePercent") } }
    @Published var useCrossMargin: Bool { didSet { defaults.set(useCrossMargin, forKey: "useCrossMargin") } }
    @Published var hideAmounts: Bool { didSet { defaults.set(hideAmounts, forKey: "hideAmounts") } }
    @Published private(set) var agentAddress: String?

    // MARK: Market
    @Published var assets: [AssetInfo] = []
    @Published var contexts: [String: AssetContext] = [:]
    @Published var coin: String {
        didSet {
            guard oldValue != coin else { return }
            defaults.set(coin, forKey: "coin")
            ticket = nil
            selectedTrendline = nil
            Task { await loadCandles() }
        }
    }
    @Published var timeframe: Timeframe {
        didSet {
            guard oldValue != timeframe else { return }
            defaults.set(timeframe.rawValue, forKey: "timeframe")
            Task { await loadCandles() }
        }
    }
    @Published var candles: [Candle] = []
    @Published var mids: [String: Double] = [:]
    @Published var streamConnected = false
    @Published var loadingCandles = false

    // MARK: Account
    @Published var account = AccountState.empty
    @Published var fills: [Fill] = []
    @Published var closedTrades: [ClosedTrade] = []
    @Published var portfolio: [PortfolioPeriod: PortfolioSeries] = [:]
    @Published var plans: [TradePlan] = []
    @Published var accountError: String?
    @Published var loadingHistory = false

    // MARK: UI
    @Published var tab: MainTab = .trade
    @Published var tool: ChartTool = .cursor
    @Published var trendlines: [Trendline] = []
    @Published var selectedTrendline: UUID?
    @Published var ticket: Ticket?
    @Published var dragCloseFraction: Double = 0.5
    @Published var toasts: [Toast] = []
    @Published var busy = false
    @Published var showOnboarding = false
    @Published var pendingOrderPrices: [Int64: Double] = [:]

    private var client: HLClient
    private var stream: HLStream
    private var started = false
    private var accountTimer: Timer?
    private var historyTimer: Timer?
    private var candleRequestID = 0

    init() {
        let net = HLNetwork(rawValue: defaults.string(forKey: "network") ?? "") ?? .testnet
        network = net
        accountAddress = defaults.string(forKey: "accountAddress") ?? ""
        riskPercent = defaults.object(forKey: "riskPercent") as? Double ?? 1.0
        slippagePercent = defaults.object(forKey: "slippagePercent") as? Double ?? 1.0
        useCrossMargin = defaults.object(forKey: "useCrossMargin") as? Bool ?? true
        hideAmounts = defaults.bool(forKey: "hideAmounts")
        coin = defaults.string(forKey: "coin") ?? "BTC"
        timeframe = Timeframe(rawValue: defaults.string(forKey: "timeframe") ?? "") ?? .m15
        client = HLClient(network: net)
        stream = HLStream(network: net)
        trendlines = store.load([Trendline].self, from: "trendlines") ?? []
        plans = store.load([TradePlan].self, from: "plans") ?? []
        agentAddress = (try? loadSigner())?.address
    }

    // MARK: Derived

    var fmt: Fmt { Fmt(hidden: hideAmounts) }
    var asset: AssetInfo? { assets.first { $0.name == coin } }
    var price: Double { mids[coin] ?? candles.last?.close ?? 0 }
    var position: Position? { account.position(for: coin) }
    var coinOrders: [OpenOrder] { account.orders(for: coin) }
    var hasAccount: Bool { EthSigner.isValidAddress(accountAddress) }
    var canTrade: Bool { hasAccount && agentAddress != nil }
    var szDecimals: Int { asset?.szDecimals ?? 4 }
    var change24h: Double { contexts[coin].map { $0.prevDayPx > 0 ? (price - $0.prevDayPx) / $0.prevDayPx : 0 } ?? 0 }
    var priceTick: Double { HLFormat.tick(for: max(price, 0.0000001), szDecimals: szDecimals) }
    var coinTrendlines: [Trendline] { trendlines.filter { $0.coin == coin } }
    /// Account value used for sizing; a $10k example when no account is connected yet.
    var sizingEquity: Double { account.accountValue > 0 ? account.accountValue : 10_000 }
    var isExampleEquity: Bool { account.accountValue <= 0 }

    var riskResult: RiskResult? {
        guard let t = ticket else { return nil }
        let entry = t.isMarket ? price : t.entry
        return RiskCalculator.calculate(RiskInput(accountValue: sizingEquity, riskPercent: riskPercent, entry: entry, stopLoss: t.stopLoss,
                                                  takeProfit: t.takeProfit, maxLeverage: asset?.maxLeverage ?? 20, szDecimals: szDecimals))
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        configureStream()
        if !hasAccount { showOnboarding = true }
        await loadMeta()
        await loadCandles()
        if hasAccount {
            loadStoredFills()
            await refreshAccount()
            await refreshHistory()
        }
        accountTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
        historyTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshHistory()
                await self?.loadMeta()
            }
        }
    }

    private func configureStream() {
        stream.onCandle = { [weak self] coin, tf, candle in
            Task { @MainActor in self?.applyCandle(coin: coin, tf: tf, candle: candle) }
        }
        stream.onMids = { [weak self] mids in
            Task { @MainActor in self?.mids.merge(mids) { _, new in new } }
        }
        stream.onUserEvent = { [weak self] in
            Task { @MainActor in
                await self?.refreshAccount()
                await self?.refreshHistory()
            }
        }
        stream.onConnectionChange = { [weak self] ok in
            Task { @MainActor in self?.streamConnected = ok }
        }
        stream.start()
        stream.setCandleSubscription(coin: coin, timeframe: timeframe)
        if hasAccount { stream.setUser(accountAddress) }
    }

    private func networkChanged() {
        stream.stop()
        client = HLClient(network: network)
        stream = HLStream(network: network)
        account = .empty
        fills = []
        closedTrades = []
        portfolio = [:]
        ticket = nil
        agentAddress = (try? loadSigner())?.address
        configureStream()
        Task {
            await loadMeta()
            await loadCandles()
            loadStoredFills()
            await refreshAccount()
            await refreshHistory()
        }
    }

    private func accountChanged() {
        account = .empty
        fills = []
        closedTrades = []
        portfolio = [:]
        stream.setUser(hasAccount ? accountAddress.trimmingCharacters(in: .whitespaces) : nil)
        guard hasAccount else { return }
        Task {
            loadStoredFills()
            await refreshAccount()
            await refreshHistory()
        }
    }

    // MARK: Market data

    func loadMeta() async {
        do {
            let (a, c) = try await client.meta()
            assets = a.sorted { (c[$0.name]?.dayVolume ?? 0) > (c[$1.name]?.dayVolume ?? 0) }
            contexts = c
            if !assets.contains(where: { $0.name == coin }), let first = assets.first { coin = first.name }
        } catch {
            toast("Kon markten niet laden: \(error.localizedDescription)", .error)
        }
    }

    func loadCandles() async {
        candleRequestID += 1
        let requestID = candleRequestID
        let c = coin, tf = timeframe
        loadingCandles = true
        stream.setCandleSubscription(coin: c, timeframe: tf)
        do {
            let result = try await client.candles(coin: c, timeframe: tf)
            guard requestID == candleRequestID else { return }
            candles = result
        } catch {
            guard requestID == candleRequestID else { return }
            toast("Kon koersen niet laden: \(error.localizedDescription)", .error)
        }
        loadingCandles = false
    }

    private func applyCandle(coin c: String, tf: Timeframe, candle: Candle) {
        guard c == coin, tf == timeframe, !loadingCandles else { return }
        if let last = candles.last {
            if last.time == candle.time { candles[candles.count - 1] = candle }
            else if candle.time > last.time { candles.append(candle) }
        } else {
            candles = [candle]
        }
    }

    // MARK: Account

    func refreshAccount() async {
        guard hasAccount else { return }
        do {
            let state = try await client.accountState(user: accountAddress.trimmingCharacters(in: .whitespaces))
            account = state
            accountError = nil
            // Drop optimistic drag prices once the exchange reflects them (or the order is gone).
            pendingOrderPrices = pendingOrderPrices.filter { oid, px in
                guard let o = state.openOrders.first(where: { $0.oid == oid }) else { return false }
                return abs(o.displayPx - px) > priceTick / 2
            }
        } catch {
            accountError = error.localizedDescription
        }
    }

    private var fillsKey: String { "fills-\(network.rawValue)-\(accountAddress.lowercased().trimmingCharacters(in: .whitespaces))" }

    private func loadStoredFills() {
        fills = store.load([Fill].self, from: fillsKey) ?? []
        rebuildTrades()
    }

    func refreshHistory() async {
        guard hasAccount else { return }
        let user = accountAddress.trimmingCharacters(in: .whitespaces)
        loadingHistory = true
        defer { loadingHistory = false }
        do {
            var known = Dictionary(uniqueKeysWithValues: fills.map { ($0.tid, $0) })
            if fills.isEmpty {
                // First sync: page back through up to a year of fills.
                var since = Int64(Date().addingTimeInterval(-365 * 86400).timeIntervalSince1970 * 1000)
                for _ in 0..<20 {
                    let page = try await client.fills(user: user, since: since)
                    for f in page { known[f.tid] = f }
                    guard page.count >= 2000, let last = page.map({ $0.time }).max() else { break }
                    since = last + 1
                }
            } else {
                for f in try await client.fills(user: user) { known[f.tid] = f }
            }
            fills = known.values.sorted { $0.time < $1.time }
            store.save(fills, to: fillsKey)
            rebuildTrades()
            portfolio = try await client.portfolio(user: user)
        } catch {
            accountError = error.localizedDescription
        }
    }

    private func rebuildTrades() {
        closedTrades = TradeBuilder.build(fills: fills, plans: plans)
    }

    func refreshAll() async {
        await loadMeta()
        await loadCandles()
        await refreshAccount()
        await refreshHistory()
    }

    // MARK: Keys

    private var keyAccount: String { "agent-\(network.rawValue)" }

    func loadSigner() throws -> EthSigner {
        guard let key = Keychain.load(account: keyAccount) else { throw HLError.notConfigured }
        return try EthSigner(privateKeyHex: key)
    }

    @discardableResult
    func saveAgentKey(_ key: String) throws -> String {
        let signer = try EthSigner(privateKeyHex: key)
        try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: keyAccount)
        agentAddress = signer.address
        return signer.address
    }

    func removeAgentKey() {
        Keychain.delete(account: keyAccount)
        agentAddress = nil
    }

    // MARK: Ticket

    func newTicket(long: Bool) {
        let p = price
        guard p > 0 else { return }
        let r = { (v: Double) in HLFormat.roundPrice(v, szDecimals: self.szDecimals) }
        ticket = Ticket(entry: r(long ? p * 0.997 : p * 1.003),
                        stopLoss: r(long ? p * 0.987 : p * 1.013),
                        takeProfit: r(long ? p * 1.023 : p * 0.977),
                        isMarket: false)
        tab = .trade
    }

    func roundToTick(_ p: Double) -> Double {
        let t = priceTick
        return HLFormat.roundPrice((p / t).rounded() * t, szDecimals: szDecimals)
    }

    func placeTicket() async {
        guard let t = ticket, let a = asset, let r = riskResult else { return }
        guard r.size > 0 else { toast("Positie is te klein.", .error); return }
        guard r.notional >= 10 else { toast("Hyperliquid vereist minimaal $10 per order.", .error); return }
        guard hasAccount else { toast("Stel eerst je wallet-adres in (Instellingen).", .error); return }
        guard let signer = signerOrToast() else { return }
        busy = true
        defer { busy = false }
        do {
            let available = max(account.withdrawable, 1)
            var lev = max(r.leverage, Int((r.notional / (available * 0.95)).rounded(.up)))
            lev = min(max(lev, 1), a.maxLeverage)
            let cross = useCrossMargin && !a.onlyIsolated
            try await client.exchange(HLActions.updateLeverage(asset: a.index, isCross: cross, leverage: lev), signer: signer)

            let isBuy = r.isLong
            let entryPx = t.isMarket ? HLFormat.slippagePrice(price, isBuy: isBuy, slippage: slippagePercent / 100, szDecimals: a.szDecimals) : t.entry
            let refEntry = t.isMarket ? price : t.entry
            var reqs = [OrderRequest(asset: a, isBuy: isBuy, size: r.size, limitPx: entryPx, reduceOnly: false, kind: .limit(tif: t.isMarket ? "Ioc" : "Gtc"))]
            if let tp = t.takeProfit, isBuy ? tp > refEntry : tp < refEntry {
                reqs.append(OrderRequest(asset: a, isBuy: !isBuy, size: r.size, limitPx: tp, reduceOnly: true, kind: .trigger(triggerPx: tp, isMarket: true, tpsl: .tp)))
            }
            reqs.append(OrderRequest(asset: a, isBuy: !isBuy, size: r.size, limitPx: t.stopLoss, reduceOnly: true, kind: .trigger(triggerPx: t.stopLoss, isMarket: true, tpsl: .sl)))
            let statuses = try await client.exchange(HLActions.order(reqs, grouping: "normalTpsl"), signer: signer)

            let plan = TradePlan(coin: coin, isLong: isBuy, entry: refEntry, stopLoss: t.stopLoss, takeProfit: t.takeProfit,
                                 riskUsd: r.riskUsd, riskPercent: riskPercent)
            plans.append(plan)
            store.save(plans, to: "plans")

            switch statuses.first {
            case .filled(_, let sz, let avg)?:
                toast("Gevuld: \(fmt.size(sz, coin: coin, decimals: szDecimals)) @ \(Fmt.price(avg)) · \(lev)×", .success)
            case .resting?:
                toast("Limit \(isBuy ? "long" : "short") geplaatst @ \(Fmt.price(entryPx)) · \(lev)×", .success)
            default:
                toast("Order verstuurd.", .success)
            }
            ticket = nil
            await refreshAccount()
        } catch {
            toast(error.localizedDescription, .error)
        }
    }

    // MARK: Orders & position management

    private func signerOrToast() -> EthSigner? {
        do { return try loadSigner() } catch {
            toast("Voeg eerst je API-wallet toe in Instellingen om te kunnen handelen.", .error)
            return nil
        }
    }

    func moveOrder(oid: Int64, to newPrice: Double) async {
        guard let o = account.openOrders.first(where: { $0.oid == oid }),
              let a = assets.first(where: { $0.name == o.coin }),
              let signer = signerOrToast() else { pendingOrderPrices[oid] = nil; return }
        let px = HLFormat.roundPrice(newPrice, szDecimals: a.szDecimals)
        let posSize = abs(account.position(for: o.coin)?.size ?? 0)
        let size = o.size > 0 ? o.size : posSize
        let kind: OrderKind = o.isTrigger
            ? .trigger(triggerPx: px, isMarket: o.orderType.lowercased().contains("market"), tpsl: o.tpsl ?? .sl)
            : .limit(tif: "Gtc")
        let req = OrderRequest(asset: a, isBuy: o.isBuy, size: size, limitPx: px, reduceOnly: o.reduceOnly, kind: kind)
        do {
            try await client.exchange(HLActions.modify(oid: oid, order: req), signer: signer)
            toast("\(orderName(o)) verplaatst naar \(Fmt.price(px))", .success)
        } catch {
            pendingOrderPrices[oid] = nil
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    func cancelOrder(_ oid: Int64) async {
        guard let o = account.openOrders.first(where: { $0.oid == oid }),
              let a = assets.first(where: { $0.name == o.coin }),
              let signer = signerOrToast() else { return }
        do {
            try await client.exchange(HLActions.cancel(asset: a.index, oid: oid), signer: signer)
            toast("\(orderName(o)) geannuleerd", .info)
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    /// Market close (IOC with slippage) of a fraction of the position.
    func closePosition(fraction: Double) async {
        guard let pos = position, let a = asset, let signer = signerOrToast() else { return }
        let size = min(abs(pos.size), HLFormat.roundSize(abs(pos.size) * fraction, szDecimals: a.szDecimals))
        guard size > 0 else { toast("Te kleine hoeveelheid om te sluiten.", .error); return }
        let isBuy = !pos.isLong
        let px = HLFormat.slippagePrice(price, isBuy: isBuy, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
        busy = true
        defer { busy = false }
        do {
            let st = try await client.exchange(HLActions.order([OrderRequest(asset: a, isBuy: isBuy, size: size, limitPx: px, reduceOnly: true, kind: .limit(tif: "Ioc"))]), signer: signer)
            if case .filled(_, let sz, let avg)? = st.first {
                let pnl = (avg - pos.entryPx) * sz * (pos.isLong ? 1 : -1)
                toast("\(Int(fraction * 100))% gesloten @ \(Fmt.price(avg)) · \(fmt.signedUsd(pnl)) gerealiseerd", pnl >= 0 ? .success : .info)
            } else {
                toast("Sluitorder verstuurd.", .info)
            }
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
        await refreshHistory()
    }

    /// Reduce-only limit order to close part of the position at a chosen price (from dragging the ✕ handle).
    func closeAtLimit(price target: Double) async {
        guard let pos = position, let a = asset, let signer = signerOrToast() else { return }
        let px = HLFormat.roundPrice(target, szDecimals: a.szDecimals)
        let size = min(abs(pos.size), HLFormat.roundSize(abs(pos.size) * dragCloseFraction, szDecimals: a.szDecimals))
        guard size > 0 else { return }
        do {
            try await client.exchange(HLActions.order([OrderRequest(asset: a, isBuy: !pos.isLong, size: size, limitPx: px, reduceOnly: true, kind: .limit(tif: "Gtc"))]), signer: signer)
            toast("Close-order: \(Int(dragCloseFraction * 100))% @ \(Fmt.price(px))", .success)
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    /// Adds a take-profit or stop-loss for the whole position, a short distance from the current price.
    func addPositionTpSl(_ kind: TpSl) async {
        guard let pos = position, let a = asset, let signer = signerOrToast() else { return }
        let up = (kind == .tp) == pos.isLong
        let px = HLFormat.roundPrice(price * (up ? 1.015 : 0.985), szDecimals: a.szDecimals)
        let req = OrderRequest(asset: a, isBuy: !pos.isLong, size: abs(pos.size), limitPx: px, reduceOnly: true,
                               kind: .trigger(triggerPx: px, isMarket: true, tpsl: kind))
        do {
            try await client.exchange(HLActions.order([req], grouping: "positionTpsl"), signer: signer)
            toast("\(kind == .tp ? "Take-profit" : "Stop-loss") toegevoegd @ \(Fmt.price(px)) – sleep de lijn om aan te passen", .success)
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    func orderName(_ o: OpenOrder) -> String {
        if o.isTrigger { return o.tpsl == .tp ? "Take-profit" : "Stop-loss" }
        if o.reduceOnly { return "Close-order" }
        return "Limit order"
    }

    // MARK: Chart lines

    var chartLines: [ChartLine] {
        var lines: [ChartLine] = []
        if let t = ticket {
            if let tp = t.takeProfit { lines.append(ChartLine(id: .ticketTP, price: tp, color: Palette.green, dashed: true, draggable: true)) }
            lines.append(ChartLine(id: .ticketSL, price: t.stopLoss, color: Palette.red, dashed: true, draggable: true))
            if !t.isMarket { lines.append(ChartLine(id: .ticketEntry, price: t.entry, color: Palette.blue, dashed: true, draggable: true)) }
        }
        for o in coinOrders {
            let px = pendingOrderPrices[o.oid] ?? o.displayPx
            let color: NSColor = o.isTrigger ? (o.tpsl == .tp ? Palette.green : Palette.red) : (o.reduceOnly ? Palette.orange : Palette.blue)
            lines.append(ChartLine(id: .order(o.oid), price: px, color: color, dashed: !o.isTrigger, draggable: true))
        }
        if let pos = position {
            lines.append(ChartLine(id: .position, price: pos.entryPx, color: pos.isLong ? Palette.blue : Palette.accent, dashed: false, draggable: false, emphasized: true))
        }
        return lines
    }

    /// Live label for a chart line at a (possibly dragged) price.
    func lineLabel(_ id: LineID, at px: Double) -> String {
        let f = fmt
        let eq = max(account.accountValue, 1)
        switch id {
        case .ticketEntry:
            guard let r = riskResult else { return "ENTRY \(Fmt.price(px))" }
            return "LIMIT \(r.isLong ? "LONG" : "SHORT")  \(f.size(r.size, coin: coin, decimals: szDecimals))  ·  \(r.leverage)×"
        case .ticketSL:
            guard let r = riskResult else { return "SL \(Fmt.price(px))" }
            return "SL  \(f.signedUsd(-r.riskUsd))  (−\(Fmt.number(riskPercent, decimals: 2))%)"
        case .ticketTP:
            guard let r = riskResult, let profit = r.potentialProfit else { return "TP \(Fmt.price(px))" }
            return "TP  \(f.signedUsd(profit))  (\(Fmt.percent(profit / sizingEquity, decimals: 1)))  ·  \(Fmt.number(r.rewardRisk ?? 0, decimals: 1))R"
        case .order(let oid):
            guard let o = account.openOrders.first(where: { $0.oid == oid }) else { return "" }
            if let pos = position, o.reduceOnly || o.isTrigger {
                let qty = o.size > 0 ? min(o.size, abs(pos.size)) : abs(pos.size)
                let pnl = (px - pos.entryPx) * qty * (pos.isLong ? 1 : -1)
                let name = o.isTrigger ? (o.tpsl == .tp ? "TP" : "SL") : "SLUIT \(Int((qty / abs(pos.size) * 100).rounded()))%"
                return "\(name)  \(f.signedUsd(pnl))  (\(Fmt.percent(pnl / eq, decimals: 1)))"
            }
            return "LIMIT \(o.isBuy ? "LONG" : "SHORT")  \(f.size(o.size, coin: coin, decimals: szDecimals))"
        case .position:
            guard let pos = position else { return "" }
            let u = (price - pos.entryPx) * pos.size
            return "\(pos.isLong ? "LONG" : "SHORT") \(f.size(pos.size, coin: coin, decimals: szDecimals))  \(f.signedUsd(u))  (\(Fmt.percent(u / eq, decimals: 2)))"
        }
    }

    func closeGhostLabel(at px: Double) -> String {
        guard let pos = position else { return "" }
        let qty = abs(pos.size) * dragCloseFraction
        let pnl = (px - pos.entryPx) * qty * (pos.isLong ? 1 : -1)
        return "SLUIT \(Int(dragCloseFraction * 100))%  @ \(Fmt.price(px))  \(fmt.signedUsd(pnl))"
    }

    func chartLineDragged(_ id: LineID, price raw: Double, ended: Bool) {
        let px = roundToTick(raw)
        switch id {
        case .ticketEntry: ticket?.entry = px
        case .ticketSL: ticket?.stopLoss = px
        case .ticketTP: ticket?.takeProfit = px
        case .order(let oid):
            pendingOrderPrices[oid] = px
            if ended { Task { await moveOrder(oid: oid, to: px) } }
        case .position: break
        }
    }

    // MARK: Trendlines

    func addTrendline(_ a: ChartPoint, _ b: ChartPoint) {
        let line = Trendline(coin: coin, a: a, b: b)
        trendlines.append(line)
        selectedTrendline = line.id
        saveTrendlines()
    }

    func updateTrendline(_ line: Trendline) {
        guard let i = trendlines.firstIndex(where: { $0.id == line.id }) else { return }
        trendlines[i] = line
        saveTrendlines()
    }

    func deleteTrendline(_ id: UUID) {
        trendlines.removeAll { $0.id == id }
        if selectedTrendline == id { selectedTrendline = nil }
        saveTrendlines()
    }

    func deleteSelectedTrendline() {
        if let id = selectedTrendline { deleteTrendline(id) }
    }

    func clearTrendlines() {
        trendlines.removeAll { $0.coin == coin }
        selectedTrendline = nil
        saveTrendlines()
    }

    private func saveTrendlines() { store.save(trendlines, to: "trendlines") }

    // MARK: Toasts

    func toast(_ text: String, _ kind: Toast.Kind = .info) {
        let t = Toast(text: text, kind: kind)
        withAnimation(.easeOut(duration: 0.2)) { toasts.append(t) }
        let delay: Double = kind == .error ? 7 : 4
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.3)) { self?.toasts.removeAll { $0.id == t.id } }
        }
    }
}
#endif
