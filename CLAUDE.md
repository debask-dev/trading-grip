# Grip – notes for Claude

Native macOS trading app (SwiftUI + AppKit) for Hyperliquid perps. Everything is built in the cloud: there is no local Xcode.

## Working with the owner
- Talk in **Dutch**. The app is bilingual: Dutch is the source language, English comes from `Sources/Grip/App/Translations.swift`.
- After **every** build, give the download link: `https://github.com/debask-dev/trading-grip/actions/runs/<run id>` → Artifacts "Grip-0.1.N".
- No demo videos unless asked. The workflow `demo-video.yml` only runs for commits containing `[video]`.
- For design questions: first propose (often as an HTML mock-up artifact), ask, then build. Keep screen space small.
- Be honest about what was tested. CI cannot place real orders. Say when something was only built, or only tested against the practice exchange.
- Never show or store private keys outside the macOS Keychain. Only an **API wallet** (agent) key is used. Refuse the main wallet key, mask addresses.

## Build and check
- Core logic lives in `Sources/GripCore` (platform-independent, tested on Linux): `export PATH=/opt/swift/usr/bin:$PATH && swift test`.
- The app lives in `Sources/Grip`. Every file is wrapped in `#if os(macOS)`, so Linux can only check syntax: `swiftc -parse <file>`.
- Real compile: push to `main`. GitHub Actions "Build Grip" (macos-15, Xcode 16.4) runs the tests, `scripts/build-app.sh` (universal, ad-hoc signed, zip) and a smoke test.
  - The smoke test makes `screen-*.png`, `cpu.txt`, `sample.txt` and `log.txt` (artifact "screenshots-…"). Always look at the screenshot.
  - Check a run: `gh api "repos/debask-dev/trading-grip/actions/runs?head_sha=SHA"`. Compile errors: the job logs, `grep "error:"`.
- Pushing tags or releases is blocked by the proxy. Push with `git -c push.negotiate=true push origin main`.

## Architecture (short)
- `GripCore`:
  - `HLClient`/`HLStream`: Hyperliquid API, websocket with a watchdog.
  - `HLSigning`: msgpack + EIP-712, verified against the Python SDK.
  - `OrderPlanner`: sizing by risk or by amount, entry ladder, adding to and reducing a position, liquidation (cross uses the account value).
  - `TradeKeeper`: after fills, one stop covers the whole position, the TP ladder is placed or scaled up, and unfilled entries are cancelled. Tested end-to-end in `OrderFlowTests` against `PaperExchange`.
  - `TradeBuilder`: executions, fees, funding, net PnL.
  - `IndicatorMath`, `ChartViewport`, `Fmt` (numbers; Dutch or English).
- `Grip/App/AppState*.swift`:
  - `AppState.swift`: the state.
  - `+Ticket`: order form, placing, keeper run.
  - `+Trading`: chart actions, quick trade, screenshot.
  - `+Markets`: tabs, positions and orders on all markets, reverse.
  - `+Budget`: margin slots, total risk.
- `Grip/Chart/ChartCanvas.swift`: custom AppKit chart. The main layer redraws only on change. `ChartOverlay` holds crosshair, legend, chips and tooltips. Indicator panes (RSI) sit under the price area.
- `Grip/Views`:
  - `TradePanel`: tabs Order / Positie, `NumberField` (typing, ↑↓, ▾ presets), `RiskRewardBar`, `HoldButton`.
  - `StatusDock`: status line plus the ⌘J overview.
  - `MainView`: header, market tabs, coin picker.
- UI texts: wrap them in `T("…")` and add the English line to `Translations.swift`. `{}` stands for an interpolated value.

## Decisions taken (keep them)
- TPs are reduce-only **limit** orders. The split remembers the last one used. A single TP goes with the entry (normalTpsl). Several TPs are placed by the keeper after the fill.
- Adding to a position: max loss counts for the **whole trade**. TPs scale proportionally. The other direction asks first, and reducing happens in the Position tab. Unfilled entries are cancelled when the position closes.
- Two tabs: **Order** and **Positie**. Order is one form with a switch for the size: **Max verlies** (size from stop + max loss), **Bedrag** (margin $, position value or coins, plus leverage; stop and TP optional) or **% account** (a share of the account as margin, stop afterwards). Positie: add, reduce now or at a price, stop to BE, stop and a single TP typed in place. In code these are still `PanelMode` `.risk`, `.amount`, `.fast`, `.position`.
- Red warnings (`Plan.blockers`: stop on the wrong side, under $10, no free margin) stop the order; orange ones only tell. A market order without a stop takes a held button.
- A ladder or an add sends every entry with its own linked stop (`normalTpsl`), so the exchange protects the trade without Grip; the keeper merges them into one stop once no entry waits. Not yet checked on the real exchange.
- Kept trades (`managed`) are stored per account and apart for practice. No order is sent while the balance is unknown.
- Leverage is auto unless chosen. It never goes below the current leverage, and it fits the free margin (and the margin slot).
- Margin budget: max positions (default 3), optional max total risk of all stops.
- Indicators are chips after the OHLC line. Line indicators get a value tag on the price axis. RSI gets its own pane.

See `docs/ROADMAP.md` for open items and plans.
