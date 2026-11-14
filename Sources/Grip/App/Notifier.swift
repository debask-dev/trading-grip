#if os(macOS)
import AppKit
import UserNotifications

/// Things Grip tells you about.
enum TradeEvent: String, CaseIterable, Identifiable, Codable {
    case orderPlaced, entryFilled, takeProfit, stopLoss, positionClosed, orderProblem, connection

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orderPlaced: return "Order geplaatst"
        case .entryFilled: return "Entry gevuld (in trade)"
        case .takeProfit: return "Take-profit geraakt"
        case .stopLoss: return "Stop-loss geraakt"
        case .positionClosed: return "Trade gesloten"
        case .orderProblem: return "Order geweigerd of mislukt"
        case .connection: return "Verbinding weg / terug"
        }
    }

    /// Subtle macOS system sounds, one per kind of event.
    var sound: String {
        switch self {
        case .orderPlaced: return "Tink"
        case .entryFilled: return "Glass"
        case .takeProfit: return "Ping"
        case .stopLoss: return "Funk"
        case .positionClosed: return "Purr"
        case .orderProblem: return "Basso"
        case .connection: return "Bottle"
        }
    }

    var defaultPref: EventPref {
        switch self {
        case .orderPlaced: return EventPref(notify: false, sound: true)
        default: return EventPref(notify: true, sound: true)
        }
    }
}

struct EventPref: Codable, Equatable {
    var notify: Bool
    var sound: Bool
}

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var authorized = false
    private var asked = false

    private var center: UNUserNotificationCenter? {
        // UserNotifications needs a real app bundle (not available for a bare `swift run`).
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func setUp() {
        guard let c = center, !asked else { return }
        asked = true
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            Task { @MainActor in Notifier.shared.authorized = ok }
        }
    }

    func post(_ event: TradeEvent, title: String, body: String, pref: EventPref, important: Bool = false) {
        if pref.sound { play(event) }
        if pref.notify, let c = center {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = event.rawValue
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if important && !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func play(_ event: TradeEvent) {
        NSSound(named: NSSound.Name(event.sound))?.play()
    }

    // Show banners also while Grip is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
#endif
