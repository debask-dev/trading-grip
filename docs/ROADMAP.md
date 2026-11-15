# Grip roadmap

## Open / proposed
- **Chase order**: an entry or TP limit that follows the price (best bid/ask, post-only) until it fills. It stops at a max distance or time. This needs the l2Book websocket and only works while Grip runs. Not built yet.
- **Labels** in the chart: compact by default, with details on hover. Give entry, SL and TP of the same order one group colour or letter.
- **Long and short at once (breakout, OCO)**: stop entries on both sides, and Grip cancels the other side after a fill. Parked by the owner.
- **⌘K command line** ("close eth 50", "sol 4h"). Proposed; it can be the basis for the AI link.
- Funding and open interest history as indicator panes.

## Later (plan: claude.ai artifact "Grip plan: meer markten en overal")
- **Distribution**: first outside the App Store (Developer ID + notarization, Sparkle updates, Paddle/Lemon Squeezy). The App Store is risky: guideline 3.1.5(iii) asks for crypto licences, and Hyperliquid has none. The owner has no developer account yet.
- **Server mode** on a Mac mini. The same app runs as a login item and is the always-on keeper: TP ladders, stop resize, OCO, orders with a time limit. Never host users' keys ourselves.
- **Sync**: Hyperliquid itself is the source of truth for orders, positions and fills. Only Grip's own state needs syncing (managed trades, plans, drawings, settings, tabs), via CloudKit (needs a developer account) or the server.
- **Keys**: one API wallet per device (no key travels between devices; each can be revoked). iCloud Keychain is optional.
- `scheduleCancel` (dead man's switch) cancels **all** orders, so do not use it as a safety net.
- **AI (MCP)**:
  - Read-only by default. Trades in two steps: the AI proposes, the user approves in Grip. Optional limits for automatic approval, and an audit log.
  - Claude runs locally. ChatGPT goes via the server.
- **iPhone**: start with "follow and manage" (no new trades). Native later, sharing GripCore.
