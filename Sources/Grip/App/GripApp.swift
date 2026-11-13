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
            Divider()
            Button("Trendlijn tekenen") { state.tool = .trendline }
                .keyboardShortcut("t", modifiers: .option)
            Button("Geselecteerde trendlijn verwijderen") { state.deleteSelectedTrendline() }
                .disabled(state.selectedTrendline == nil)
            Divider()
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
