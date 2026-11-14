#if os(macOS)
import SwiftUI
import GripCore

@main
struct GripApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Grip", id: "main") {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { GripCommands(state: state) }

        Window("Accounts", id: "accounts") {
            AccountsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 900, height: 680)
        .keyboardShortcut("a", modifiers: [.command, .shift])

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM binary (e.g. `swift run`); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct GripCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Chart") {
            ForEach(Array(Timeframe.allCases.enumerated()), id: \.element) { i, tf in
                Button("Timeframe \(tf.label)") { state.timeframe = tf }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
            Button("Vorige timeframe") { state.stepTimeframe(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Volgende timeframe") { state.stepTimeframe(1) }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button(state.tool == .trendline ? "Trendlijn stoppen" : "Trendlijn") { state.toggleTool(.trendline) }
                .keyboardShortcut("t", modifiers: .option)
            Button(state.tool == .horizontal ? "Horizontale lijn stoppen" : "Horizontale lijn") { state.toggleTool(.horizontal) }
                .keyboardShortcut("h", modifiers: .option)
            Button(state.magnet ? "Magneet uit" : "Magneet aan") { state.magnet.toggle() }
                .keyboardShortcut("m", modifiers: .option)
            Button("Geselecteerde lijn verwijderen") { state.deleteSelectedTrendline() }
                .disabled(state.selectedTrendline == nil)
            Divider()
            Button("Chart resetten") { state.resetChart() }
                .keyboardShortcut("r", modifiers: .option)
            Button("Vernieuwen") { Task { await state.refreshAll() } }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Trade") {
            Button("Nieuwe long") { state.newTicket(long: true) }
                .keyboardShortcut("l", modifiers: .option)
            Button("Nieuwe short") { state.newTicket(long: false) }
                .keyboardShortcut("s", modifiers: .option)
            Button("Order annuleren (ticket)") { state.ticket = nil }
                .disabled(state.ticket == nil)
            Divider()
            Button(state.hideAmounts ? "Bedragen tonen" : "Bedragen verbergen") { state.hideAmounts.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Sneltoetsen") { state.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
        }

        CommandGroup(before: .toolbar) {
            ForEach(Array(MainTab.allCases.enumerated()), id: \.element) { i, tab in
                Button(tab.label) { state.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
            }
            Divider()
        }
    }
}
#endif
