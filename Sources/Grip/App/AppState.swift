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

enum ChartTool: Equatable { case cursor, trendline, horizontal, measure }

/// One take-profit of the ladder in the ticket.
struct TPLevel: Equatable, Identifiable {
    var id = UUID()
    var price: Double
    var pct: Double          // % of the position
}

enum SizeLock: String { case risk, size }

/// The three trade tabs.
enum PanelMode: String, CaseIterable, Identifiable {
    case risk, amount, position
    var id: String { rawValue }
    var label: String {
        switch self {
        case .risk: return "Risico"
        case .amount: return "Bedrag"
        case .position: return "Positie"
        }
    }
    /// Stored value from older versions (risk / quick / manual).
    static func stored(_ raw: String?) -> PanelMode {
        switch raw {
        case "amount", "quick", "manual": return .amount
        case "position": return .position
        default: return .risk
        }
    }
}

/// How the size is typed in the Bedrag tab and when adding.
enum AmountUnit: String, CaseIterable {
    case margin, notional, coin
    func label(coin: String) -> String {
        switch self {
        case .margin: return "$ marge"
        case .notional: return "$ positie"
        case .coin: return coin
        }
    }
    var next: AmountUnit {
        switch self {
        case .margin: return .notional
        case .notional: return .coin
        case .coin: return .margin
        }
    }
}

/// The order being prepared on the chart before it is sent ("Nieuwe order").
struct Ticket: Equatable {
    var isLong: Bool
    /// One or more entries (price + share of the new size).
    var entries: [TPLevel]
    var stopLoss: Double
    var useStopLoss = true
    var tps: [TPLevel]
    var isMarket: Bool                // first entry at market
    var lock: SizeLock = .risk
    var size: Double? = nil           // coins, set by hand (lock on size, or the manual panel)
    var leverage: Int? = nil          // nil = automatic (minimum needed, never below the current leverage)
    var moveSLToBreakEven = false
    /// Opposite of the open position: makes it smaller (Positie tab).
    var reduceOnly = false
    /// Bedrag tab, adding and reducing: the size as typed, in `amountUnit`.
    var amount: Double = 0
    var amountUnit: AmountUnit = .margin
    /// Sized by your max loss (Risico) instead of by the amount.
    var riskSized = true

    var entry: Double {
        get { entries.first?.price ?? 0 }
        set { if entries.isEmpty { entries = [TPLevel(price: newValue, pct: 100)] } else { entries[0].price = newValue } }
    }
    var takeProfit: Double? { tps.first?.price }
}

struct HourStats: Equatable {
    var change: Double
    var high: Double
    var low: Double
    var volume: Double
    var volumeUsd: Double
}

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    var text: String
    var kind: Kind
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum LineID: Hashable {
    case ticketEntry(Int), ticketSL, ticketTP(Int), ticketLiq, pendingTP(Int), order(Int64), position, breakEven, liquidation
}

/// A buy/sell marker on the chart.
struct ChartMarker: Identifiable, Equatable {
    let id: String
    let time: Int64
    let price: Double
    let isBuy: Bool
    let label: String
    let detail: [String]
    let tradeID: String
}

/// Dotted connector from average entry to average exit of a closed trade.
struct ChartTradeLink: Identifiable, Equatable {
    let id: String
    let t0: Int64, p0: Double
    let t1: Int64, p1: Double
    let isWin: Bool
    let label: String
}

/// A question with OK / Cancel before something irreversible (market orders).
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let destructive: Bool
    let action: () -> Void
}

struct ChartFocus: Equatable {
    let start: Int64
    let end: Int64
    let token: Int
}

struct ChartLine: Identifiable, Equatable {
    var id: LineID
    var price: Double
    var color: NSColor
    var dashed: Bool
    var draggable: Bool
    var emphasized: Bool = false
    var closable: Bool = false
}

@MainActor
final class AppState: ObservableObject {
    private let defaults = UserDefaults.standard
    let store = JSONStore()

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
    /// Magnet: drawing and measuring always snap to candle open/high/low/close (⌘ inverts it temporarily).
    @Published var magnet: Bool { didSet { defaults.set(magnet, forKey: "magnet") } }
    @Published var chartStyle: ChartStyle { didSet { saveJSON(chartStyle, "chartStyle") } }
    /// Appearance for new trendlines; follows the last change made in the line toolbar.
    @Published var lineAppearance: LineAppearance { didSet { saveJSON(lineAppearance, "lineAppearance") } }
    @Published private(set) var agentAddress: String?
    /// Connected exchange accounts (public info only; keys are in the Keychain).
    @Published var accounts: [ExchangeAccount] = [] { didSet { saveJSON(accounts, "accounts") } }
    @Published var activeAccountID: UUID? { didSet { if !isDemoVideo { defaults.set(activeAccountID?.uuidString, forKey: "activeAccountID") } } }
    @Published var securityNotice: String?
    /// Oefenmodus: live prices, simulated orders and balance (no keys needed).
    @Published var paperMode: Bool {
        didSet {
            guard oldValue != paperMode else { return }
            if !isDemoVideo { defaults.set(paperMode, forKey: "paperMode") }
            modeChanged()
        }
    }
    /// True when launched with -GripDemoVideo YES (scripted screen recording).
    let isDemoVideo: Bool

    // MARK: Market
    @Published var assets: [AssetInfo] = []
    @Published var contexts: [String: AssetContext] = [:]
    @Published var coin: String {
        didSet {
            guard oldValue != coin else { return }
            defaults.set(coin, forKey: "coin")
            ticket = nil
            selectedTrendline = nil
            hourStats = nil
            Task { await loadCandles(); await refreshHourStats() }
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
    /// Mid prices for the UI, published at most once a second (Hyperliquid sends all ~200 markets several times a second).
    @Published var mids: [String: Double] = [:]
    /// Latest mids, unthrottled (paper fills, order prices).
    var liveMids: [String: Double] = [:]
    private var midsFlushScheduled = false
    private var pendingCandle: (coin: String, tf: Timeframe, candle: Candle)?
    private var candleFlushScheduled = false
    private var tickPublishScheduled = false
    private var latestTick: Candle?
    // Caches so a redraw does not recompute everything
    var markerCacheKey = ""
    var markerCache: [ChartMarker] = []
    var linkCache: [ChartTradeLink] = []
    var planCacheKey: PlanKey?
    var planCache: Plan?
    var reconcileAgain = false
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
    weak var chartCanvas: ChartCanvas?
    // Fees, funding and order types (for labelled executions and net results)
    @Published var feeRates: FeeRates = .base
    @Published var fundingPayments: [FundingPayment] = []
    @Published var orderKinds: [Int64: OrderKindTag] = [:]
    @Published var analysis = TradeAnalysis(closed: [], open: [:])
    @Published var pendingConfirm: ConfirmRequest?
    @Published var chartFocus: ChartFocus?
    @Published var highlightTradeID: String?
    @Published var confirmMarketOrders: Bool = UserDefaults.standard.object(forKey: "confirmMarketOrders") as? Bool ?? true {
        didSet { defaults.set(confirmMarketOrders, forKey: "confirmMarketOrders") }
    }
    /// Buy/sell markers on the chart: 0 = off, -1 = current trade only, otherwise number of days.
    @Published var markerDays: Int = UserDefaults.standard.object(forKey: "markerDays") as? Int ?? 7 {
        didSet { defaults.set(markerDays, forKey: "markerDays") }
    }
    @Published var showMenuBar: Bool = UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true {
        didSet { defaults.set(showMenuBar, forKey: "showMenuBar") }
    }
    @Published var eventPrefs: [String: EventPref] = AppState.loadJSON([String: EventPref].self, "eventPrefs") ?? [:] {
        didSet { saveJSON(eventPrefs, "eventPrefs") }
    }
    @Published var panelMode: PanelMode = PanelMode.stored(UserDefaults.standard.string(forKey: "panelMode")) {
        didSet { defaults.set(panelMode.rawValue, forKey: "panelMode"); panelModeChanged(oldValue) }
    }
    /// Last used take-profit split, e.g. [50, 30, 20].
    @Published var lastSplit: [Double] = UserDefaults.standard.array(forKey: "lastSplit") as? [Double] ?? [50, 30, 20] {
        didSet { defaults.set(lastSplit, forKey: "lastSplit") }
    }
    // Bedrag tab: last used values
    @Published var amountValue: Double = UserDefaults.standard.object(forKey: "amountValue") as? Double ?? 50 { didSet { defaults.set(amountValue, forKey: "amountValue") } }
    @Published var amountUnit: AmountUnit = AmountUnit(rawValue: UserDefaults.standard.string(forKey: "amountUnit") ?? "") ?? .margin { didSet { defaults.set(amountUnit.rawValue, forKey: "amountUnit") } }
    @Published var amountLev: Int = UserDefaults.standard.object(forKey: "amountLev") as? Int ?? 5 { didSet { defaults.set(amountLev, forKey: "amountLev") } }
    @Published var amountUseStop: Bool = UserDefaults.standard.object(forKey: "amountUseStop") as? Bool ?? true { didSet { defaults.set(amountUseStop, forKey: "amountUseStop") } }
    @Published var amountSLPct: Double = UserDefaults.standard.object(forKey: "amountSLPct") as? Double ?? 1.0 { didSet { defaults.set(amountSLPct, forKey: "amountSLPct") } }
    @Published var amountUseTP: Bool = UserDefaults.standard.object(forKey: "amountUseTP") as? Bool ?? false { didSet { defaults.set(amountUseTP, forKey: "amountUseTP") } }
    @Published var amountTPPct: Double = UserDefaults.standard.object(forKey: "amountTPPct") as? Double ?? 2.0 { didSet { defaults.set(amountTPPct, forKey: "amountTPPct") } }
    /// Stop / take-profit fields show % from the entry instead of a price.
    @Published var stopInPct: Bool = UserDefaults.standard.bool(forKey: "stopInPct") { didSet { defaults.set(stopInPct, forKey: "stopInPct") } }
    @Published var tpInPct: Bool = UserDefaults.standard.bool(forKey: "tpInPct") { didSet { defaults.set(tpInPct, forKey: "tpInPct") } }
    @Published var showMoreOptions: Bool = UserDefaults.standard.bool(forKey: "showMoreOptions") { didSet { defaults.set(showMoreOptions, forKey: "showMoreOptions") } }
    @Published var quickUsd: Double = UserDefaults.standard.object(forKey: "quickUsd") as? Double ?? 1000 { didSet { defaults.set(quickUsd, forKey: "quickUsd") } }
    @Published var quickLev: Int = UserDefaults.standard.object(forKey: "quickLev") as? Int ?? 5 { didSet { defaults.set(quickLev, forKey: "quickLev") } }
    @Published var quickSLPct: Double = UserDefaults.standard.object(forKey: "quickSLPct") as? Double ?? 0.5 { didSet { defaults.set(quickSLPct, forKey: "quickSLPct") } }
    @Published var quickTPPct: Double = UserDefaults.standard.object(forKey: "quickTPPct") as? Double ?? 1.0 { didSet { defaults.set(quickTPPct, forKey: "quickTPPct") } }
    @Published var managed: [String: ManagedTrade] = AppState.loadJSON([String: ManagedTrade].self, "managedTrades") ?? [:] {
        didSet { saveJSON(managed, "managedTrades") }
    }
    var reconciling = false
    /// Coins whose stop moves to break-even after the first take-profit.
    @Published var breakEvenAfterTP: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "breakEvenAfterTP") ?? []) {
        didSet { defaults.set(Array(breakEvenAfterTP), forKey: "breakEvenAfterTP") }
    }
    @Published var hourStats: HourStats?
    @Published var screenshotFolder: String = UserDefaults.standard.string(forKey: "screenshotFolder")
        ?? (FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.appendingPathComponent("Grip").path ?? NSHomeDirectory()) {
        didSet { defaults.set(screenshotFolder, forKey: "screenshotFolder") }
    }
    @Published var screenshotToClipboard: Bool = UserDefaults.standard.object(forKey: "screenshotToClipboard") as? Bool ?? true {
        didSet { defaults.set(screenshotToClipboard, forKey: "screenshotToClipboard") }
    }
    private var lastFeeFetch = Date.distantPast
    private var previousOrders: [OpenOrder] = []
    @Published var chartResetToken = 0
    @Published var showShortcuts = false
    private var demo: DemoDirector?

    private(set) var client: HLClient
    private var stream: HLStream
    private var started = false
    private var accountTimer: Timer?
    private var historyTimer: Timer?
    private var hourTimer: Timer?
    private var candleRequestID = 0
    private(set) var paper: PaperExchange
    private var paperKey: String { isDemoVideo ? "paper-demo" : "paper-\(network.rawValue)" }

    init() {
        // The demo recording uses live mainnet prices (read-only) with simulated orders.
        let demoRun = UserDefaults.standard.bool(forKey: "GripDemoVideo")
        let storedNet = HLNetwork(rawValue: UserDefaults.standard.string(forKey: "network") ?? "") ?? .testnet
        let loaded = demoRun ? (accounts: [ExchangeAccount](), active: UUID?.none, notice: String?.none) : Self.loadAccounts(network: storedNet)
        let activeAcct = loaded.accounts.first { $0.id == loaded.active }
        let net = demoRun ? .mainnet : (activeAcct?.network ?? storedNet)
        network = net
        if let a = activeAcct {
            accountAddress = a.address
        } else if case .address(let a) = Credentials.classify(UserDefaults.standard.string(forKey: "accountAddress") ?? "") {
            accountAddress = a
        } else {
            accountAddress = ""
        }
        accounts = loaded.accounts
        activeAccountID = loaded.active
        securityNotice = loaded.notice
        riskPercent = defaults.object(forKey: "riskPercent") as? Double ?? 1.0
        slippagePercent = defaults.object(forKey: "slippagePercent") as? Double ?? 1.0
        useCrossMargin = defaults.object(forKey: "useCrossMargin") as? Bool ?? true
        hideAmounts = defaults.bool(forKey: "hideAmounts")
        magnet = defaults.bool(forKey: "magnet")
        var style = Self.loadJSON(ChartStyle.self, "chartStyle") ?? .grip
        // Untouched old default → the new default with #E68538 for falling candles.
        if style == .greenRed { style = .grip }
        chartStyle = style
        var appearance = Self.loadJSON(LineAppearance.self, "lineAppearance") ?? LineAppearance()
        if appearance.color == "#F5D547" { appearance.color = LineSwatches.defaultColor }   // old default → your TradingView color
        lineAppearance = appearance
        coin = defaults.string(forKey: "coin") ?? "BTC"
        timeframe = Timeframe(rawValue: defaults.string(forKey: "timeframe") ?? "") ?? .m15
        let demo = UserDefaults.standard.bool(forKey: "GripDemoVideo")
        isDemoVideo = demo
        paperMode = demo || defaults.bool(forKey: "paperMode")
        if demo {
            paper = PaperExchange(balance: 25_000)
            coin = "BTC"
            timeframe = .m15
            riskPercent = 0.5
            hideAmounts = false
        } else {
            paper = JSONStore().load(PaperExchange.self, from: "paper-\(net.rawValue)") ?? PaperExchange(balance: 10_000)
        }
        client = HLClient(network: net)
        stream = HLStream(network: net)
        trendlines = demo ? [] : (store.load([Trendline].self, from: "trendlines") ?? [])
        plans = demo ? [] : (store.load([TradePlan].self, from: "plans") ?? [])
        agentAddress = (try? loadSigner())?.address
    }

    // MARK: Derived

    var fmt: Fmt { Fmt(hidden: hideAmounts) }
    var selectedLine: Trendline? { trendlines.first { $0.id == selectedTrendline } }

    private func saveJSON<T: Encodable>(_ v: T, _ key: String) {
        if !isDemoVideo, let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ t: T.Type, _ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    var asset: AssetInfo? { assets.first { $0.name == coin } }
    /// Last traded price: the live candle close (updates with every trade), the mid as fallback.
    var price: Double { candles.last?.close ?? mids[coin] ?? 0 }
    var position: Position? { account.position(for: coin) }
    var coinOrders: [OpenOrder] { account.orders(for: coin) }
    var hasAccount: Bool { paperMode || EthSigner.isValidAddress(accountAddress) }
    var canTrade: Bool { paperMode || (hasAccount && agentAddress != nil) }
    var paperStartingBalance: Double { paper.startingBalance }
    var szDecimals: Int { asset?.szDecimals ?? 4 }
    var change24h: Double { contexts[coin].map { $0.prevDayPx > 0 ? (price - $0.prevDayPx) / $0.prevDayPx : 0 } ?? 0 }
    var priceTick: Double { HLFormat.tick(for: max(price, 0.0000001), szDecimals: szDecimals) }
    var coinTrendlines: [Trendline] { trendlines.filter { $0.coin == coin } }
    /// Account value used for sizing; a $10k example when no account is connected yet.
    var sizingEquity: Double { account.accountValue > 0 ? account.accountValue : 10_000 }
    var isExampleEquity: Bool { account.accountValue <= 0 }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if !isDemoVideo { Notifier.shared.setUp() }
        configureStream()
        observeSystem()
        // Launch arguments for automated screenshots: -GripSkipOnboarding YES -GripDemoTicket YES
        if !hasAccount && !defaults.bool(forKey: "GripSkipOnboarding") { showOnboarding = true }
        await loadMeta()
        await loadCandles()
        if defaults.bool(forKey: "GripDemoTicket") { newTicket(long: true) }
        if isDemoVideo {
            paperChanged()
            let d = DemoDirector(state: self)
            demo = d
            d.run()
        }
        if hasAccount {
            loadStoredFills()
            await refreshAccount()
            await refreshHistory()
        }
        accountTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
        await refreshHourStats()
        hourTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshHourStats() }
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
            Task { @MainActor in self?.queueCandle(coin: coin, tf: tf, candle: candle) }
        }
        stream.onMids = { [weak self] mids in
            Task { @MainActor in
                guard let self else { return }
                self.liveMids.merge(mids) { _, new in new }
                if self.paperMode { self.paperTick() }
                if !self.midsFlushScheduled {
                    self.midsFlushScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self else { return }
                        self.midsFlushScheduled = false
                        if self.mids != self.liveMids { self.mids = self.liveMids }
                    }
                }
            }
        }
        stream.onUserEvent = { [weak self] in
            Task { @MainActor in
                await self?.refreshAccount()
                await self?.refreshHistory()
            }
        }
        stream.onConnectionChange = { [weak self] ok in
            Task { @MainActor in
                guard let self, self.streamConnected != ok else { return }
                let wasConnected = self.streamConnected
                self.streamConnected = ok
                if wasConnected && !ok { self.notify(.connection, "Verbinding met Hyperliquid weg", "Grip probeert opnieuw te verbinden…") }
            }
        }
        stream.start()
        stream.setCandleSubscription(coin: coin, timeframe: timeframe)
        if hasAccount { stream.setUser(accountAddress) }
    }

    func reconnectStream() { stream.forceReconnect() }

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
        if !isDemoVideo { paper = store.load(PaperExchange.self, from: paperKey) ?? PaperExchange(balance: 10_000) }
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

    /// Every trade sends a candle update. The chart gets it directly (~8×/s, no SwiftUI involved);
    /// the rest of the window (header price, labels) at most twice a second.
    private func queueCandle(coin c: String, tf: Timeframe, candle: Candle) {
        guard c == coin, tf == timeframe, !loadingCandles else { return }
        pendingCandle = (c, tf, candle)
        guard !candleFlushScheduled else { return }
        candleFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.candleFlushScheduled = false
            guard let p = self.pendingCandle, p.coin == self.coin, p.tf == self.timeframe else { return }
            self.pendingCandle = nil
            self.chartCanvas?.applyLive(p.candle)
            let isNew = p.candle.time > (self.candles.last?.time ?? 0)
            if isNew || self.candles.isEmpty { self.applyCandle(coin: p.coin, tf: p.tf, candle: p.candle); return }
            self.latestTick = p.candle
            if !self.tickPublishScheduled {
                self.tickPublishScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    self.tickPublishScheduled = false
                    if let t = self.latestTick { self.latestTick = nil; self.applyCandle(coin: self.coin, tf: self.timeframe, candle: t) }
                }
            }
        }
    }

    private func applyCandle(coin c: String, tf: Timeframe, candle: Candle) {
        guard c == coin, tf == timeframe, !loadingCandles else { return }
        if let last = candles.last {
            if last.time == candle.time { if last != candle { candles[candles.count - 1] = candle } }
            else if candle.time > last.time { candles.append(candle) }
        } else {
            candles = [candle]
        }
    }

    // MARK: Account

    func refreshAccount() async {
        if paperMode {
            paper.recordSnapshot(marks: marks(), assets: assets, minInterval: isDemoVideo ? 2_000 : 30_000)
            account = paper.accountState(marks: marks(), assets: assets)
            portfolio = paper.portfolio()
            if !isDemoVideo { store.save(paper, to: paperKey) }
            await reconcileManaged()
            return
        }
        guard hasAccount else { return }
        do {
            let state = try await client.accountState(user: accountAddress.trimmingCharacters(in: .whitespaces))
            // Position or orders changed (a fill, a TP/SL hit): fetch the fills now instead of waiting.
            let oldPositions = Dictionary(account.positions.map { ($0.coin, $0.size) }, uniquingKeysWith: { a, _ in a })
            let newPositions = Dictionary(state.positions.map { ($0.coin, $0.size) }, uniquingKeysWith: { a, _ in a })
            let changed = oldPositions != newPositions || Set(account.openOrders.map(\.oid)) != Set(state.openOrders.map(\.oid))
            if changed && !(account.positions.isEmpty && account.openOrders.isEmpty && previousOrders.isEmpty) {
                Task { await self.refreshHistory() }
            }
            for o in state.openOrders where orderKinds[o.oid] == nil {
                orderKinds[o.oid] = o.isTrigger ? (o.tpsl == .tp ? .takeProfit : .stopLoss) : (o.reduceOnly ? .takeProfit : .limit)
            }
            previousOrders = state.openOrders
            if account != state { account = state }
            await reconcileManaged()
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
        if paperMode { paperChanged(); return }
        fills = store.load([Fill].self, from: fillsKey) ?? []
        fundingPayments = store.load([FundingPayment].self, from: fillsKey.replacingOccurrences(of: "fills-", with: "funding-")) ?? []
        orderKinds = (store.load([String: OrderKindTag].self, from: fillsKey.replacingOccurrences(of: "fills-", with: "orderkinds-")) ?? [:])
            .reduce(into: [:]) { acc, kv in if let k = Int64(kv.key) { acc[k] = kv.value } }
        rebuildTrades()
    }

    func refreshHistory() async {
        if paperMode { paperChanged(); return }
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
            let previousTids = Set(fills.map(\.tid))
            let merged = known.values.sorted { $0.time < $1.time }
            let newFills = previousTids.isEmpty ? [] : merged.filter { !previousTids.contains($0.tid) }

            if Date().timeIntervalSince(lastFeeFetch) > 3600, let rates = try? await client.feeRates(user: user) {
                feeRates = rates
                lastFeeFetch = Date()
            }
            if let kinds = try? await client.orderKinds(user: user) { orderKinds.merge(kinds) { _, new in new } }
            let since = (fundingPayments.map(\.time).max() ?? Int64(Date().addingTimeInterval(-365 * 86400).timeIntervalSince1970 * 1000)) + 1
            if let fresh = try? await client.funding(user: user, since: since), !fresh.isEmpty {
                fundingPayments = Array(Set(fundingPayments + fresh)).sorted { $0.time < $1.time }
            }

            fills = merged
            store.save(fills, to: fillsKey)
            store.save(fundingPayments, to: fillsKey.replacingOccurrences(of: "fills-", with: "funding-"))
            store.save(Dictionary(uniqueKeysWithValues: orderKinds.map { (String($0.key), $0.value) }), to: fillsKey.replacingOccurrences(of: "fills-", with: "orderkinds-"))
            rebuildTrades()
            announce(newFills)
            portfolio = try await client.portfolio(user: user)
        } catch {
            accountError = error.localizedDescription
        }
    }

    private func rebuildTrades() {
        analysis = TradeBuilder.analyze(fills: fills, plans: plans, funding: fundingPayments, orderKinds: orderKinds)
        closedTrades = analysis.closed
    }

    func refreshAll() async {
        await loadMeta()
        await loadCandles()
        await refreshAccount()
        await refreshHistory()
        await refreshHourStats()
    }

    // MARK: Keys

    private var keyAccount: String { activeAccount?.keychainAccount ?? "agent-\(network.rawValue)" }

    func loadSigner() throws -> EthSigner {
        guard let key = Keychain.load(account: keyAccount) else { throw HLError.notConfigured }
        return try EthSigner(privateKeyHex: key)
    }

    // MARK: Orders & position management

    func requireSigner() throws -> EthSigner {
        do { return try loadSigner() } catch {
            throw HLError.exchange("Dit account is alleen-lezen. Voeg een API-wallet toe in het accountscherm (⇧⌘A) om te handelen.")
        }
    }

    /// Current prices for paper fills (mids, plus the chart's last close as fallback).
    func marks() -> [String: Double] {
        var m = liveMids
        if m[coin] == nil, let c = candles.last?.close { m[coin] = c }
        return m
    }

    func execOrders(_ reqs: [OrderRequest], grouping: String = "na") async throws -> [OrderStatus] {
        if paperMode {
            let st = try paper.place(reqs, grouping: grouping, marks: marks())
            paperChanged()
            return st
        }
        return try await client.exchange(HLActions.order(reqs, grouping: grouping), signer: try requireSigner())
    }

    func execModify(oid: Int64, _ req: OrderRequest) async throws {
        if paperMode { try paper.modify(oid: oid, to: req); paperChanged(); return }
        try await client.exchange(HLActions.modify(oid: oid, order: req), signer: try requireSigner())
    }

    func execCancel(_ a: AssetInfo, oid: Int64) async throws {
        if paperMode { try paper.cancel(oid: oid); paperChanged(); return }
        try await client.exchange(HLActions.cancel(asset: a.index, oid: oid), signer: try requireSigner())
    }

    func execLeverage(_ a: AssetInfo, isCross: Bool, leverage: Int) async throws {
        if paperMode { paper.updateLeverage(coin: a.name, isCross: isCross, leverage: leverage); return }
        try await client.exchange(HLActions.updateLeverage(asset: a.index, isCross: isCross, leverage: leverage), signer: try requireSigner())
    }

    // MARK: Paper trading

    private func paperChanged() {
        account = paper.accountState(marks: marks(), assets: assets)
        fills = paper.fills
        orderKinds = paper.orderKinds
        fundingPayments = []
        feeRates = .base
        rebuildTrades()
        portfolio = paper.portfolio()
        pendingOrderPrices = [:]
        if !isDemoVideo { store.save(paper, to: paperKey) }
    }

    /// Called on every price update in paper mode: fills resting orders that were hit.
    private func paperTick() {
        let filled = paper.onPrices(marks())
        if filled.isEmpty {
            account = paper.accountState(marks: marks(), assets: assets)
            return
        }
        paperChanged()
        announce(filled)
        Task { await reconcileManaged() }
    }

    func resetPaper(balance: Double) {
        paper.reset(balance: balance)
        paperChanged()
        toast("Oefenaccount gereset naar \(fmt.usd(balance))", .info)
    }

    private func modeChanged() {
        account = .empty
        fills = []
        closedTrades = []
        portfolio = [:]
        ticket = nil
        pendingOrderPrices = [:]
        if paperMode { paperChanged() } else { accountChanged() }
        toast(paperMode ? "Oefenmodus aan: live koersen, gesimuleerde orders." : "Oefenmodus uit: je handelt op je echte account.", .info)
    }

    func moveOrder(oid: Int64, to newPrice: Double) async {
        guard let o = account.openOrders.first(where: { $0.oid == oid }),
              let a = assets.first(where: { $0.name == o.coin }) else { pendingOrderPrices[oid] = nil; return }
        let px = HLFormat.roundPrice(newPrice, szDecimals: a.szDecimals)
        let posSize = abs(account.position(for: o.coin)?.size ?? 0)
        let size = o.size > 0 ? o.size : posSize
        let kind: OrderKind = o.isTrigger
            ? .trigger(triggerPx: px, isMarket: o.orderType.lowercased().contains("market"), tpsl: o.tpsl ?? .sl)
            : .limit(tif: "Gtc")
        let req = OrderRequest(asset: a, isBuy: o.isBuy, size: size, limitPx: px, reduceOnly: o.reduceOnly, kind: kind)
        do {
            try await execModify(oid: oid, req)
            if o.isTrigger && o.tpsl == .sl { managed[o.coin]?.stop = px }
            toast("\(orderName(o)) verplaatst naar \(Fmt.price(px))", .success)
        } catch {
            pendingOrderPrices[oid] = nil
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    func cancelOrder(_ oid: Int64) async {
        guard let o = account.openOrders.first(where: { $0.oid == oid }),
              let a = assets.first(where: { $0.name == o.coin }) else { return }
        do {
            try await execCancel(a, oid: oid)
            if o.isTrigger && o.tpsl == .sl { managed[o.coin]?.stop = nil }   // removed on purpose: don't put it back
            toast("\(orderName(o)) geannuleerd", .info)
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    /// Market close (IOC with slippage) of a fraction of the position.
    /// Market close with confirmation (setting). Works for any coin with a position.
    func requestClose(fraction: Double, coin closeCoin: String? = nil) {
        let c = closeCoin ?? coin
        guard let pos = account.position(for: c) else { return }
        guard confirmMarketOrders else { Task { await closePosition(fraction: fraction, coin: c) }; return }
        let px = mids[c] ?? (c == coin ? price : pos.entryPx)
        let qty = abs(pos.size) * fraction
        let gross = (px - pos.entryPx) * qty * (pos.isLong ? 1 : -1)
        let fee = qty * px * feeRates.taker
        let all = fraction >= 0.999
        pendingConfirm = ConfirmRequest(
            title: all ? "Hele \(c)-positie sluiten?" : "\(Int(fraction * 100))% van je \(c)-positie sluiten?",
            message: "\(fmt.size(qty, coin: c, decimals: 4)) market · ≈ \(Fmt.price(px))\nResultaat van dit deel ≈ \(fmt.signedUsd(gross - fee, decimals: 2)) na fees" + (all ? "\nOpen TP- en SL-orders vervallen." : ""),
            confirmTitle: all ? "Alles sluiten" : "Sluit \(Int(fraction * 100))%", destructive: true) { [weak self] in
                Task { await self?.closePosition(fraction: fraction, coin: c) }
            }
    }

    func closePosition(fraction: Double, coin closeCoin: String? = nil) async {
        let c = closeCoin ?? coin
        guard let pos = account.position(for: c), let a = assets.first(where: { $0.name == c }) else { return }
        let price = mids[c] ?? (c == coin ? self.price : pos.entryPx)
        let size = min(abs(pos.size), HLFormat.roundSize(abs(pos.size) * fraction, szDecimals: a.szDecimals))
        guard size > 0 else { toast("Te kleine hoeveelheid om te sluiten.", .error); return }
        let isBuy = !pos.isLong
        let px = HLFormat.slippagePrice(price, isBuy: isBuy, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
        busy = true
        defer { busy = false }
        do {
            let st = try await execOrders([OrderRequest(asset: a, isBuy: isBuy, size: size, limitPx: px, reduceOnly: true, kind: .limit(tif: "Ioc"))])
            if case .filled? = st.first {
                // announced via `announce` when the fill arrives
            } else {
                toast("Sluitorder verstuurd.", .info)
            }
        } catch {
            toast(error.localizedDescription, .error)
            notify(.orderProblem, "Sluiten mislukt", error.localizedDescription)
        }
        await refreshAccount()
        await refreshHistory()
    }

    /// Reduce-only limit order to close part of the position at a chosen price (from dragging the ✕ handle).
    func closeAtLimit(price target: Double) async {
        guard let pos = position, let a = asset else { return }
        let px = HLFormat.roundPrice(target, szDecimals: a.szDecimals)
        let size = min(abs(pos.size), HLFormat.roundSize(abs(pos.size) * dragCloseFraction, szDecimals: a.szDecimals))
        guard size > 0 else { return }
        do {
            _ = try await execOrders([OrderRequest(asset: a, isBuy: !pos.isLong, size: size, limitPx: px, reduceOnly: true, kind: .limit(tif: "Gtc"))])
            toast("Close-order: \(Int(dragCloseFraction * 100))% @ \(Fmt.price(px))", .success)
        } catch {
            toast(error.localizedDescription, .error)
        }
        await refreshAccount()
    }

    /// Adds a take-profit or stop-loss for the whole position, a short distance from the current price.
    func addPositionTpSl(_ kind: TpSl) async {
        guard let pos = position, let a = asset else { return }
        let up = (kind == .tp) == pos.isLong
        let px = HLFormat.roundPrice(price * (up ? 1.015 : 0.985), szDecimals: a.szDecimals)
        let req = OrderRequest(asset: a, isBuy: !pos.isLong, size: abs(pos.size), limitPx: px, reduceOnly: true,
                               kind: .trigger(triggerPx: px, isMarket: true, tpsl: kind))
        do {
            _ = try await execOrders([req], grouping: "positionTpsl")
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
        let t = ticket
        if let t {
            let pl = plan
            for (i, tp) in t.tps.enumerated() where !t.reduceOnly {
                lines.append(ChartLine(id: .ticketTP(i), price: tp.price, color: Palette.green, dashed: true, draggable: true, closable: true))
            }
            if t.useStopLoss && !t.reduceOnly {
                lines.append(ChartLine(id: .ticketSL, price: t.stopLoss, color: Palette.red, dashed: true, draggable: true))
            }
            for (i, e) in t.entries.enumerated() where !(t.isMarket && i == 0) {
                lines.append(ChartLine(id: .ticketEntry(i), price: e.price, color: t.reduceOnly ? Palette.orange : (pl?.isAdd == true ? Palette.accent : Palette.blue),
                                       dashed: true, draggable: true, closable: true))
            }
            if let pl, !t.reduceOnly, pl.estLiquidationPx > 0 {
                lines.append(ChartLine(id: .ticketLiq, price: pl.estLiquidationPx, color: Palette.red.withAlphaComponent(0.7), dashed: true, draggable: false))
            }
        }
        // Take-profits that wait for the entry to fill.
        if let pend = managed[coin]?.tps {
            for (i, px) in pend.prices.enumerated() {
                lines.append(ChartLine(id: .pendingTP(i), price: px, color: Palette.green.withAlphaComponent(0.45), dashed: true, draggable: false))
            }
        }
        // While adding, the ticket's stop line stands for the position's stop.
        let hideStop = t.map { $0.useStopLoss && !$0.reduceOnly && position != nil } ?? false
        for o in coinOrders where !(hideStop && o.isTrigger && o.tpsl == .sl) {
            let px = pendingOrderPrices[o.oid] ?? o.displayPx
            let color: NSColor = o.isTrigger ? (o.tpsl == .tp ? Palette.green : Palette.red) : (o.reduceOnly ? Palette.orange : Palette.blue)
            lines.append(ChartLine(id: .order(o.oid), price: px, color: color, dashed: !o.isTrigger, draggable: true, closable: true))
        }
        if let pos = position {
            lines.append(ChartLine(id: .position, price: pos.entryPx, color: pos.isLong ? Palette.blue : Palette.accent, dashed: false, draggable: false, emphasized: true, closable: true))
            if let be = breakEven { lines.append(ChartLine(id: .breakEven, price: be, color: Palette.muted, dashed: true, draggable: false)) }
            if let liq = pos.liquidationPx, liq > 0 { lines.append(ChartLine(id: .liquidation, price: liq, color: Palette.red.withAlphaComponent(0.8), dashed: true, draggable: false)) }
        }
        return lines
    }

    /// Live label for a chart line at a (possibly dragged) price.
    func lineLabel(_ id: LineID, at px: Double) -> String {
        let f = fmt
        let eq = max(account.accountValue, 1)
        switch id {
        case .ticketEntry(let i):
            guard let t = ticket, let pl = plan else { return "ENTRY \(Fmt.price(px))" }
            let sz = pl.entrySizes.indices.contains(i) ? pl.entrySizes[i] : 0
            if t.reduceOnly { return "VERKLEIN \(f.size(sz, coin: coin, decimals: szDecimals))  ·  \(f.signedUsd(pl.reducePnl ?? 0))" }
            let side = t.isLong ? "LONG" : "SHORT"
            if t.entries.count == 1 {
                return "\(pl.isAdd ? "BIJ" : "LIMIT") \(side)  \(f.size(sz, coin: coin, decimals: szDecimals))  ·  \(t.leverage ?? pl.leverage)×"
            }
            return "E\(i + 1) · \(Int(t.entries[i].pct))%  \(f.size(sz, coin: coin, decimals: szDecimals))"
        case .ticketSL:
            guard let pl = plan, let risk = pl.riskUsd else { return "SL \(Fmt.price(px))" }
            return "SL\(pl.isAdd ? " hele positie" : "")  \(f.signedUsd(-risk))  (−\(Fmt.number(pl.riskPercentActual ?? 0, decimals: 2))%)"
        case .ticketTP(let i):
            guard let t = ticket, t.tps.indices.contains(i), let pl = plan else { return "TP \(Fmt.price(px))" }
            let lvl = t.tps[i]
            let avg = pl.after.avgEntry
            let qty = pl.after.size * lvl.pct / 100
            let profit = qty * (t.isLong ? px - avg : avg - px) - qty * feeRates.maker * (avg + px)
            let rr = t.useStopLoss ? " · \(Fmt.number(abs(px - avg) / max(abs(avg - t.stopLoss), 1e-12), decimals: 1))R" : ""
            return "TP\(i + 1) · \(Int(lvl.pct))%  \(f.signedUsd(profit))\(rr)"
        case .ticketLiq:
            return "LIQ ≈ \(Fmt.price(px))"
        case .pendingTP(let i):
            let n = managed[coin]?.tps?.prices.count ?? 1
            let pct = Int(((managed[coin]?.tps?.fractions[safe: i] ?? 1) * 100).rounded())
            return "TP\(n > 1 ? "\(i + 1)" : "") · \(pct)%  wacht op entry"
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
            let net = positionNet ?? 0
            return "\(pos.isLong ? "LONG" : "SHORT") \(f.size(pos.size, coin: coin, decimals: szDecimals))  ·  gem. \(Fmt.price(pos.entryPx))  ·  netto \(f.signedUsd(net, decimals: 2))  (\(Fmt.percent(net / eq, decimals: 2)))"
        case .breakEven:
            return "BE \(Fmt.price(px))  ·  break-even na fees\((openTrade?.funding ?? 0) != 0 ? " + funding" : "")"
        case .liquidation:
            return "LIQ \(Fmt.price(px))"
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
        case .ticketEntry(let i): if ticket?.entries.indices.contains(i) == true { ticket?.entries[i].price = px }
        case .ticketSL: ticket?.stopLoss = px
        case .ticketTP(let i): if ticket?.tps.indices.contains(i) == true { ticket?.tps[i].price = px }
        case .ticketLiq, .pendingTP: break
        case .order(let oid):
            pendingOrderPrices[oid] = px
            if ended { Task { await moveOrder(oid: oid, to: px) } }
        case .position, .breakEven, .liquidation: break
        }
    }

    // MARK: Trendlines

    func addTrendline(_ a: ChartPoint, _ b: ChartPoint) {
        let line = Trendline(coin: coin, a: a, b: b, appearance: lineAppearance)
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

    /// ⌥H / ⌥V: a horizontal or vertical line where the mouse is.
    func addLineAtCursor(vertical: Bool) {
        guard let p = chartCanvas?.cursorPoint() else { toast("Beweeg de muis over de chart en druk dan nog eens.", .info); return }
        if vertical {
            var ap = lineAppearance
            ap.extendLeft = true
            ap.extendRight = true
            let line = Trendline(coin: coin, a: p, b: ChartPoint(time: p.time, price: p.price * 1.001), appearance: ap)
            trendlines.append(line)
            selectedTrendline = line.id
            saveTrendlines()
        } else {
            addHorizontal(p)
        }
    }

    /// Horizontal line across the whole chart at a price.
    func addHorizontal(_ p: ChartPoint) {
        var ap = lineAppearance
        ap.extendLeft = true
        ap.extendRight = true
        let line = Trendline(coin: coin, a: p, b: ChartPoint(time: p.time + timeframe.milliseconds, price: p.price), appearance: ap)
        trendlines.append(line)
        selectedTrendline = line.id
        saveTrendlines()
    }

    func toggleTool(_ t: ChartTool) { tool = tool == t ? .cursor : t }

    func resetChart() { chartResetToken += 1 }

    func stepTimeframe(_ d: Int) {
        if let tf = d > 0 ? timeframe.next : timeframe.previous { timeframe = tf }
    }

    /// Changes the selected line from the toolbar; the new look becomes the default for new lines.
    func styleSelectedLine(_ change: (inout LineAppearance) -> Void) {
        guard var l = selectedLine else { return }
        var ap = l.appearance
        change(&ap)
        l.appearance = ap
        updateTrendline(l)
        lineAppearance = ap
    }

    func deleteSelectedTrendline() {
        if let id = selectedTrendline { deleteTrendline(id) }
    }

    func clearTrendlines() {
        trendlines.removeAll { $0.coin == coin }
        selectedTrendline = nil
        saveTrendlines()
    }

    private func saveTrendlines() { if !isDemoVideo { store.save(trendlines, to: "trendlines") } }

    // MARK: Toasts

    func toast(_ text: String, _ kind: Toast.Kind = .info) {
        if kind == .error { NSLog("Grip error: %@", text) }
        let t = Toast(text: text, kind: kind)
        withAnimation(.easeOut(duration: 0.2)) { toasts.append(t) }
        let delay: Double = kind == .error ? 7 : 4
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.3)) { self?.toasts.removeAll { $0.id == t.id } }
        }
    }
}
// MARK: - Sleep / wake

extension AppState {
    /// After sleep or a network change the socket can be dead without an error: reconnect and reload.
    func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wakeUp(reason: "wake") }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let last = self.candles.last else { return }
                // The newest candle should be at most one candle old.
                let age = Date().timeIntervalSince1970 * 1000 - Double(last.time)
                if age > Double(self.timeframe.milliseconds) * 2 { self.wakeUp(reason: "stale") }
            }
        }
    }

    func wakeUp(reason: String) {
        reconnectStream()
        Task { await refreshAll() }
    }

    /// Manual refresh (button / ⌘R): reconnect live data and reload everything.
    func refreshEverything() {
        reconnectStream()
        Task {
            await refreshAll()
            toast("Ververst", .info)
        }
    }
}

// MARK: - Trade results, notifications, chart markers

extension AppState {
    var openTrade: OpenTrade? { analysis.open[coin] }

    /// Net result of the whole open trade if closed now: realized partials + open PnL − fees (paid + exit) + funding.
    func net(for pos: Position) -> Double {
        let o = analysis.open[pos.coin]
        let px = mids[pos.coin] ?? (pos.coin == coin ? price : pos.entryPx)
        return PositionMath.net(price: px, entry: pos.entryPx, size: pos.size, feesPaid: o?.feesPaid ?? 0,
                                realized: o?.realized ?? 0, funding: o?.funding ?? 0, takerRate: feeRates.taker)
    }

    var positionNet: Double? { position.map { net(for: $0) } }

    var breakEven: Double? {
        guard let pos = position else { return nil }
        let o = openTrade
        return PositionMath.breakEven(entry: pos.entryPx, size: pos.size, feesPaid: o?.feesPaid ?? 0, realized: o?.realized ?? 0,
                                      funding: o?.funding ?? 0, takerRate: feeRates.taker)
    }

    func pref(_ e: TradeEvent) -> EventPref { eventPrefs[e.rawValue] ?? e.defaultPref }

    func notify(_ e: TradeEvent, _ title: String, _ body: String) {
        Notifier.shared.post(e, title: title, body: body, pref: pref(e), important: e == .entryFilled || e == .stopLoss || e == .takeProfit || e == .positionClosed)
    }

    /// Turns new fills into clear messages: entry, take-profit, stop-loss, closed trade with net result.
    func announce(_ newFills: [Fill]) {
        guard !newFills.isEmpty else { return }
        let byOrder = Dictionary(grouping: newFills) { "\($0.coin)-\($0.oid)" }
        for (_, group) in byOrder.sorted(by: { ($0.value.first?.time ?? 0) < ($1.value.first?.time ?? 0) }) {
            guard let first = group.first else { continue }
            let c = first.coin
            let qty = group.reduce(0) { $0 + $1.sz }
            let px = group.reduce(0) { $0 + $1.px * $1.sz } / max(qty, 1e-12)
            let start = group.map(\.startPosition).first ?? 0
            let end = start + group.reduce(0) { $0 + ($1.isBuy ? $1.sz : -$1.sz) }
            let opening = abs(end) > abs(start) - 1e-12 && (start == 0 || (start > 0) == (end > 0))
            let sizeText = fmt.size(qty, coin: c, decimals: 4)
            if opening {
                let side = end > 0 ? "Long" : "Short"
                notify(.entryFilled, start == 0 ? "\(side) \(c) geopend" : "\(side) \(c) bijgekocht", "\(sizeText) @ \(Fmt.price(px))")
                toast("\(start == 0 ? "In trade" : "Bijgekocht"): \(side.lowercased()) \(sizeText) @ \(Fmt.price(px))", .success)
                continue
            }
            let realized = group.reduce(0) { $0 + $1.closedPnl - $1.fee }
            let kind = orderKinds[first.oid]
            if abs(end) < 1e-9, let trade = analysis.closed.first(where: { $0.coin == c }) {
                let r = trade.rMultiple.map { " · " + Fmt.number($0, decimals: 1) + "R" } ?? ""
                let how = kind == .stopLoss ? "Stop-loss" : (kind == .takeProfit ? "Take-profit" : "Gesloten")
                notify(trade.isWin ? .positionClosed : (kind == .stopLoss ? .stopLoss : .positionClosed),
                       "\(c)-trade gesloten (\(how))", "Netto \(fmt.signedUsd(trade.netPnl, decimals: 2))\(r) · fees \(fmt.usd(trade.fees, decimals: 2))")
                toast("Trade gesloten: netto \(fmt.signedUsd(trade.netPnl, decimals: 2))\(r)", trade.isWin ? .success : .info)
            } else if kind == .stopLoss {
                notify(.stopLoss, "Stop-loss \(c) geraakt", "\(sizeText) @ \(Fmt.price(px)) · \(fmt.signedUsd(realized, decimals: 2))")
                toast("Stop-loss geraakt: \(sizeText) @ \(Fmt.price(px))", .info)
            } else {
                let label = analysis.open[c]?.executions.last(where: { $0.oid == first.oid })?.label ?? "Deel"
                if kind == .takeProfit && breakEvenAfterTP.contains(c) {
                    Task { await self.refreshAccount(); await self.moveStopToBreakEven(coin: c) }
                }
                notify(kind == .takeProfit ? .takeProfit : .positionClosed, "\(label) \(c) gevuld", "\(sizeText) gesloten @ \(Fmt.price(px)) · \(fmt.signedUsd(realized, decimals: 2))")
                toast("\(label) gevuld: \(sizeText) @ \(Fmt.price(px)) · \(fmt.signedUsd(realized, decimals: 2))", realized >= 0 ? .success : .info)
            }
        }
    }

    /// Markers for the current coin, according to the marker setting.
    /// Markers and trade links only change with new fills or settings: computed once, not on every redraw.
    private func refreshMarkerCache() {
        let key = "\(coin)|\(markerDays)|\(hideAmounts)|\(analysis.executions.count)|\(analysis.closed.count)|\(fills.last?.tid ?? 0)|\(analysis.open[coin]?.executions.count ?? 0)"
        guard key != markerCacheKey else { return }
        markerCacheKey = key
        markerCache = computeMarkers()
        linkCache = computeLinks()
    }

    var chartMarkers: [ChartMarker] { refreshMarkerCache(); return markerCache }
    var chartTradeLinks: [ChartTradeLink] { refreshMarkerCache(); return linkCache }

    private func computeMarkers() -> [ChartMarker] {
        guard markerDays != 0 else { return [] }
        let f = fmt
        var execs: [Execution]
        if markerDays < 0 {
            execs = analysis.open[coin]?.executions ?? []
        } else {
            let from = Int64(Date().addingTimeInterval(-Double(markerDays) * 86400).timeIntervalSince1970 * 1000)
            execs = analysis.executions.filter { $0.coin == coin && $0.time >= from }
        }
        return execs.map { e in
            let when = Date(timeIntervalSince1970: Double(e.time) / 1000).formatted(date: .abbreviated, time: .shortened)
            var lines = ["\(e.label) · \(e.isBuy ? "Koop" : "Verkoop") \(f.size(e.size, coin: e.coin, decimals: 4))",
                         "@ \(Fmt.price(e.price))  ·  \(when)",
                         "Fee \(f.usd(e.fee, decimals: 2))\(e.fills > 1 ? "  ·  \(e.fills) fills" : "")"]
            if e.role == .exit { lines.append("Resultaat \(f.signedUsd(e.closedPnl - e.fee, decimals: 2))") }
            return ChartMarker(id: e.id, time: e.time, price: e.price, isBuy: e.isBuy, label: e.label, detail: lines, tradeID: e.tradeID)
        }
    }

    private func computeLinks() -> [ChartTradeLink] {
        guard markerDays > 0 else { return [] }
        let from = Date().addingTimeInterval(-Double(markerDays) * 86400)
        return analysis.closed.filter { $0.coin == coin && $0.closeTime >= from }.map { t in
            let r = t.rMultiple.map { " · " + Fmt.number($0, decimals: 1) + "R" } ?? ""
            return ChartTradeLink(id: t.id, t0: Int64(t.openTime.timeIntervalSince1970 * 1000), p0: t.avgEntry,
                                  t1: Int64(t.closeTime.timeIntervalSince1970 * 1000), p1: t.avgExit,
                                  isWin: t.isWin, label: fmt.signedUsd(t.netPnl, decimals: 2) + r)
        }
    }

    /// Shows a closed trade on the chart (from History).
    func show(trade t: ClosedTrade) {
        let dur = t.duration
        let tf: Timeframe = dur < 3 * 3600 ? .m5 : dur < 24 * 3600 ? .m15 : dur < 5 * 86400 ? .h1 : dur < 30 * 86400 ? .h4 : .d1
        if markerDays >= 0 && markerDays < 3650 && t.closeTime < Date().addingTimeInterval(-Double(max(markerDays, 0)) * 86400) { markerDays = 3650 }
        coin = t.coin
        timeframe = tf
        tab = .trade
        highlightTradeID = t.id
        chartFocus = ChartFocus(start: Int64(t.openTime.timeIntervalSince1970 * 1000), end: Int64(t.closeTime.timeIntervalSince1970 * 1000),
                                token: (chartFocus?.token ?? 0) + 1)
    }

    var menuBarTitle: String {
        let positions = account.positions
        guard !positions.isEmpty else { return "Grip" }
        let total = positions.reduce(0) { $0 + net(for: $1) }
        if positions.count == 1, let p = positions.first { return "\(p.coin) \(fmt.signedUsd(total, decimals: 2))" }
        return "\(positions.count) pos. \(fmt.signedUsd(total, decimals: 2))"
    }
}

// MARK: - Accounts

enum ConnectionStatus: Equatable {
    case paper, none, readOnly, trading, error(String)
}

extension AppState {
    var activeAccount: ExchangeAccount? { accounts.first { $0.id == activeAccountID } }

    var connectionStatus: ConnectionStatus {
        if paperMode { return .paper }
        guard activeAccount != nil else { return .none }
        if let e = accountError { return .error(e) }
        return agentAddress == nil ? .readOnly : .trading
    }

    /// Makes an account the one Grip trades with (switches network and address).
    func activate(_ id: UUID?) {
        activeAccountID = id
        guard let a = activeAccount else {
            accountAddress = ""
            reloadAgent()
            return
        }
        if paperMode { paperMode = false }
        if network != a.network { network = a.network }
        accountAddress = a.address
        reloadAgent()
        toast("Actief account: \(a.label)", .success)
    }

    /// Saves a new or edited account. `key` = API-wallet private key (nil keeps the current one, "" = read-only).
    func saveAccount(_ account: ExchangeAccount, key: String?) throws {
        var a = account
        if let key {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Keychain.delete(account: a.keychainAccount)
                a.agentAddress = nil
            } else {
                let signer = try EthSigner(privateKeyHex: trimmed)
                try Keychain.save(trimmed, account: a.keychainAccount)
                a.agentAddress = signer.address
            }
        }
        if let i = accounts.firstIndex(where: { $0.id == a.id }) {
            accounts[i] = a
            if activeAccountID == a.id { reloadAgent() }
        } else {
            accounts.append(a)
            activate(a.id)
        }
    }

    func removeAccount(_ id: UUID) {
        guard let a = accounts.first(where: { $0.id == id }) else { return }
        Keychain.delete(account: a.keychainAccount)
        accounts.removeAll { $0.id == id }
        if activeAccountID == id { activate(accounts.first?.id) }
        toast("Account “\(a.label)” verwijderd (ook de sleutel uit de sleutelhanger).", .info)
    }

    func renameAccount(_ id: UUID, to label: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].label = label
    }

    func reloadAgent() {
        agentAddress = (try? loadSigner())?.address
        Task { await refreshAccount() }
    }

    /// Runs the connection test for an address and (optional) key.
    func testConnection(network: HLNetwork, address: String, key: String?,
                        progress: @escaping @Sendable ([CheckStep]) async -> Void) async -> ConnectionReport {
        let other: HLNetwork = network.isMainnet ? .testnet : .mainnet
        return await ConnectionTester.run(api: HLClient(network: network), otherNetworkAPI: HLClient(network: other),
                                          network: network, address: address, agentKey: key, progress: progress)
    }

    /// Re-tests a saved account with its stored key and remembers the result.
    func testAccount(_ id: UUID, progress: @escaping @Sendable ([CheckStep]) async -> Void) async -> ConnectionReport? {
        guard let a = accounts.first(where: { $0.id == id }) else { return nil }
        let key = Keychain.load(account: a.keychainAccount)
        let report = await testConnection(network: a.network, address: a.address, key: key, progress: progress)
        if let i = accounts.firstIndex(where: { $0.id == id }) {
            accounts[i].lastCheck = Date()
            accounts[i].lastCheckOK = report.passed
            if report.agentName != nil { accounts[i].agentName = report.agentName }
            if report.agentValidUntil != nil { accounts[i].agentValidUntil = report.agentValidUntil }
        }
        return report
    }

    /// Moves settings from version 0.1 (one address + one key per network) to accounts, and removes
    /// a private key that was pasted into the address field.
    static func loadAccounts(network net: HLNetwork) -> (accounts: [ExchangeAccount], active: UUID?, notice: String?) {
        let d = UserDefaults.standard
        var accounts: [ExchangeAccount] = d.data(forKey: "accounts").flatMap { try? JSONDecoder().decode([ExchangeAccount].self, from: $0) } ?? []
        var active = d.string(forKey: "activeAccountID").flatMap(UUID.init(uuidString:))
        var notice: String?
        let legacy = d.string(forKey: "accountAddress") ?? ""
        switch Credentials.classify(legacy) {
        case .privateKey:
            d.removeObject(forKey: "accountAddress")
            notice = "In het adresveld stond een private key in plaats van een adres. Grip heeft die verwijderd. Was het de sleutel van je hoofdwallet, zet je geld dan voor de zekerheid over naar een nieuwe wallet. Was het een API-wallet, maak dan een nieuwe aan."
        case .address(let addr) where accounts.isEmpty:
            for n in [net] + HLNetwork.allCases.filter({ $0 != net }) {
                let legacyKey = "agent-\(n.rawValue)"
                let key = Keychain.load(account: legacyKey)
                if n != net && key == nil { continue }
                var acct = ExchangeAccount(network: n, label: "Hyperliquid \(n.isMainnet ? "Mainnet" : "Testnet")", address: addr)
                if let key, let signer = try? EthSigner(privateKeyHex: key) {
                    do {
                        try Keychain.save(key, account: acct.keychainAccount)
                        Keychain.delete(account: legacyKey)
                        acct.agentAddress = signer.address
                    } catch {}
                }
                accounts.append(acct)
            }
            active = accounts.first?.id
            if let data = try? JSONEncoder().encode(accounts) { d.set(data, forKey: "accounts") }
            d.set(active?.uuidString, forKey: "activeAccountID")
        default:
            break
        }
        if let a = active, !accounts.contains(where: { $0.id == a }) { active = nil }
        return (accounts, active, notice)
    }
}
#endif
