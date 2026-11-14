import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live market data over Hyperliquid's WebSocket: candles for the visible chart and all mid prices.
/// Reconnects automatically. Callbacks arrive on the main queue.
public final class HLStream: NSObject, @unchecked Sendable {
    public var onCandle: ((String, Timeframe, Candle) -> Void)?
    public var onMids: (([String: Double]) -> Void)?
    public var onUserEvent: (() -> Void)?
    public var onConnectionChange: ((Bool) -> Void)?

    private let network: HLNetwork
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var subscriptions: [[String: Any]] = []
    private var candleSub: (coin: String, tf: Timeframe)?
    private var user: String?
    private var pingTimer: Timer?
    private var reconnectDelay: TimeInterval = 1
    private var stopped = false
    private var watchdog: Timer?
    /// When the last message arrived (mid prices arrive about every second).
    public private(set) var lastMessage = Date()

    public init(network: HLNetwork) {
        self.network = network
        super.init()
    }

    public func start() {
        stopped = false
        connect()
        DispatchQueue.main.async { [weak self] in
            self?.watchdog?.invalidate()
            // A socket can die silently (sleep, network switch). No message for 20 s = reconnect.
            self?.watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self, !self.stopped else { return }
                if Date().timeIntervalSince(self.lastMessage) > 20 { self.forceReconnect() }
            }
        }
    }

    /// Drops the current socket and connects again right away (e.g. after the Mac wakes up).
    public func forceReconnect() {
        guard !stopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        reconnectDelay = 1
        lastMessage = Date()
        DispatchQueue.main.async { [weak self] in self?.onConnectionChange?(false) }
        connect()
    }

    public func stop() {
        stopped = true
        watchdog?.invalidate()
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    public func setCandleSubscription(coin: String, timeframe: Timeframe) {
        if let old = candleSub {
            send(["method": "unsubscribe", "subscription": ["type": "candle", "coin": old.coin, "interval": old.tf.rawValue]])
        }
        candleSub = (coin, timeframe)
        send(["method": "subscribe", "subscription": ["type": "candle", "coin": coin, "interval": timeframe.rawValue]])
    }

    private static let userChannels = ["userEvents", "userFills", "orderUpdates"]

    public func setUser(_ address: String?) {
        if let old = user {
            for t in Self.userChannels { send(["method": "unsubscribe", "subscription": ["type": t, "user": old]]) }
        }
        user = address
        subscribeUser()
    }

    private func subscribeUser() {
        guard let user else { return }
        for t in Self.userChannels { send(["method": "subscribe", "subscription": ["type": t, "user": user]]) }
    }

    private func connect() {
        guard !stopped else { return }
        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: network.wsURL)
        self.task = task
        task.resume()
        receive()
        send(["method": "subscribe", "subscription": ["type": "allMids"]])
        if let c = candleSub {
            send(["method": "subscribe", "subscription": ["type": "candle", "coin": c.coin, "interval": c.tf.rawValue]])
        }
        subscribeUser()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.send(["method": "ping"])
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { self.onConnectionChange?(false) }
                self.scheduleReconnect()
            case .success(let message):
                self.reconnectDelay = 1
                var data: Data?
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: break
                }
                if let data { self.handle(data) }
                self.receive()
            }
        }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        task = nil
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.connect() }
    }

    private func handle(_ data: Data) {
        lastMessage = Date()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = obj["channel"] as? String else { return }
        switch channel {
        case "subscriptionResponse":
            DispatchQueue.main.async { self.onConnectionChange?(true) }
        case "candle":
            guard let c = obj["data"] as? [String: Any], let candle = HLClient.parseCandle(c),
                  let coin = c["s"] as? String, let i = c["i"] as? String, let tf = Timeframe(rawValue: i) else { return }
            DispatchQueue.main.async { self.onCandle?(coin, tf, candle) }
        case "allMids":
            guard let d = obj["data"] as? [String: Any], let mids = d["mids"] as? [String: String] else { return }
            var out: [String: Double] = [:]
            for (k, v) in mids { if let x = Double(v) { out[k] = x } }
            DispatchQueue.main.async { self.onMids?(out) }
        case "user", "userEvents", "userFills", "orderUpdates":
            // Fills and order changes: refresh right away (a snapshot on subscribe is skipped).
            if (obj["data"] as? [String: Any])?["isSnapshot"] as? Bool == true { return }
            DispatchQueue.main.async { self.onUserEvent?() }
        default:
            break
        }
    }
}
