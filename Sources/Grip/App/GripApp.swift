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

        // Only write when it really changes: the menu bar controller sets this binding on every update,
        // and an unconditional write would trigger a new update forever.
        MenuBarExtra(isInserted: Binding(get: { state.showMenuBar }, set: { if state.showMenuBar != $0 { state.showMenuBar = $0 } })) {
            MenuBarView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        } label: {
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

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
            Button("Markt openen in nieuwe tab") { state.tab = .trade; state.showMarketPicker = true }
                .keyboardShortcut("t", modifiers: .command)
            Button("Volgende markt") { state.selectTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Vorige markt") { state.selectTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            ForEach(1..<10) { n in
                Button("Markt \(n)") { state.selectTab(number: n) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .control)
            }
            Button(state.dockExpanded ? "Overzicht inklappen" : "Overzicht posities en orders") { state.dockExpanded.toggle() }
                .keyboardShortcut("j", modifiers: .command)
            Divider()
            Button(state.tool == .trendline ? "Trendlijn stoppen" : "Trendlijn") { state.toggleTool(.trendline) }
                .keyboardShortcut("t", modifiers: .option)
            Button("Horizontale lijn op cursor") { state.addLineAtCursor(vertical: false) }
                .keyboardShortcut("h", modifiers: .option)
            Button("Verticale lijn op cursor") { state.addLineAtCursor(vertical: true) }
                .keyboardShortcut("v", modifiers: .option)
            Button(state.tool == .measure ? "Meten stoppen" : "Meten") { state.toggleTool(.measure) }
            Button(state.magnet ? "Magneet uit" : "Magneet aan") { state.magnet.toggle() }
                .keyboardShortcut("m", modifiers: .option)
            Button("Geselecteerde lijn verwijderen") { state.deleteSelectedTrendline() }
                .disabled(state.selectedTrendline == nil)
            Divider()
            Button("Chart resetten") { state.resetChart() }
                .keyboardShortcut("r", modifiers: .option)
            Button("Vernieuwen") { state.refreshEverything() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Screenshot van chart") { state.takeScreenshot() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Screenshotmap openen") { state.revealScreenshotFolder() }
        }

        CommandMenu("Trade") {
            Button("Nieuwe long") { state.newTicket(long: true) }
                .keyboardShortcut("l", modifiers: .option)
            Button("Nieuwe short") { state.newTicket(long: false) }
                .keyboardShortcut("s", modifiers: .option)
            Button("Order annuleren (ticket)") { state.ticket = nil }
                .disabled(state.ticket == nil)
            Divider()
            Button("Market long (Bedrag)") { state.quickTrade(long: true) }
                .keyboardShortcut("b", modifiers: .option)
            Button("Market short (Bedrag)") { state.quickTrade(long: false) }
                .keyboardShortcut("n", modifiers: .option)
            Button("Positie sluiten") { state.quickClose() }
                .keyboardShortcut("x", modifiers: .option)
                .disabled(state.position == nil)
            Divider()
            Picker("Tabblad", selection: $state.panelMode) {
                ForEach(PanelMode.allCases) { Text($0.label).tag($0) }
            }
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
