#if os(macOS)
import SwiftUI
import GripCore

@main
struct GripApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window(T("Grip"), id: "main") {
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
            // The Grip "G" as a template image (follows the menu bar colour), plus the result when something is open.
            Image(nsImage: GripLogo.menuBar)
            if let title = state.menuBarTitle { Text(title) }
        }
        .menuBarExtraStyle(.window)

        Window(T("Accounts"), id: "accounts") {
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

    /// With the menu bar icon on, closing the window leaves Grip running: it keeps stops and take-profits in line
    /// and can be opened again from the menu bar. Without the icon there is no way back, so then it quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true)
    }
}

struct GripCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu(T("Chart")) {
            ForEach(Array(Timeframe.allCases.enumerated()), id: \.element) { i, tf in
                Button(T("Timeframe \(tf.label)")) { state.timeframe = tf }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
            Button(T("Vorige timeframe")) { state.stepTimeframe(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button(T("Volgende timeframe")) { state.stepTimeframe(1) }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button(T("Markt openen in nieuwe tab")) { state.tab = .trade; state.showMarketPicker = true }
                .keyboardShortcut("t", modifiers: .command)
            Button(T("Volgende markt")) { state.selectTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button(T("Vorige markt")) { state.selectTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            ForEach(1..<10) { n in
                Button(T("Markt \(n)")) { state.selectTab(number: n) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .control)
            }
            Button(state.dockExpanded ? T("Overzicht inklappen") : T("Overzicht posities en orders")) { state.dockExpanded.toggle() }
                .keyboardShortcut("j", modifiers: .command)
            Divider()
            Button(state.tool == .trendline ? T("Trendlijn stoppen") : T("Trendlijn")) { state.toggleTool(.trendline) }
                .keyboardShortcut("t", modifiers: .option)
            Button(T("Horizontale lijn op cursor")) { state.addLineAtCursor(vertical: false) }
                .keyboardShortcut("h", modifiers: .option)
            Button(T("Verticale lijn op cursor")) { state.addLineAtCursor(vertical: true) }
                .keyboardShortcut("v", modifiers: .option)
            Button(state.tool == .measure ? T("Meten stoppen") : T("Meten")) { state.toggleTool(.measure) }
            Button(state.magnet ? T("Magneet uit") : T("Magneet aan")) { state.magnet.toggle() }
                .keyboardShortcut("m", modifiers: .option)
            Button(T("Geselecteerde lijn verwijderen")) { state.deleteSelectedTrendline() }
                .disabled(state.selectedTrendline == nil)
            Divider()
            Button(state.showPastTrades ? T("Eerdere trades verbergen") : T("Eerdere trades tonen")) { state.showPastTrades.toggle() }
                .keyboardShortcut("p", modifiers: .option)
            // End works in the chart itself; no menu shortcut, so End keeps working in text fields.
            Button(T("Terug naar nu (End)")) { state.chartCanvas?.goToNow() }
            Button(T("Chart resetten")) { state.resetChart() }
                .keyboardShortcut("r", modifiers: .option)
            Button(T("Vernieuwen")) { state.refreshEverything() }
                .keyboardShortcut("r", modifiers: .command)
            Button(T("Screenshot van chart")) { state.takeScreenshot() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button(T("Screenshotmap openen")) { state.revealScreenshotFolder() }
        }

        CommandMenu(T("Trade")) {
            Button(T("Nieuwe long")) { state.newTicket(long: true) }
                .keyboardShortcut("l", modifiers: .option)
            Button(T("Nieuwe short")) { state.newTicket(long: false) }
                .keyboardShortcut("s", modifiers: .option)
            Button(T("Order annuleren (ticket)")) { state.ticket = nil }
                .disabled(state.ticket == nil)
            Divider()
            Button(T("Market long (Bedrag)")) { state.quickTrade(long: true) }
                .keyboardShortcut("b", modifiers: .option)
            Button(T("Market short (Bedrag)")) { state.quickTrade(long: false) }
                .keyboardShortcut("n", modifiers: .option)
            Button(T("Positie sluiten")) { state.quickClose() }
                .keyboardShortcut("x", modifiers: .option)
                .disabled(state.position == nil)
            Divider()
            Picker(T("Tabblad"), selection: $state.panelMode) {
                ForEach(PanelMode.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Button(state.hideAmounts ? T("Bedragen tonen") : T("Bedragen verbergen")) { state.hideAmounts.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button(T("Sneltoetsen")) { state.showShortcuts = true }
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
