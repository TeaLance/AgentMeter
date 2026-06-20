# CLAUDE.md

AgentMeter — a macOS 14+ menu-bar app (Swift / AppKit + SwiftUI) that reads
local Claude Code, Claude (status), and Codex usage logs and shows a live
usage/cost gauge.

## Build & test

```bash
swift build              # build all targets
swift test               # run AgentMeterCoreTests
./Scripts/bundle.sh      # produce the .app bundle
./Scripts/release.sh     # build + bundle a release
```

Two CI workflows: `gitleaks` (secret scan) and `offline-check`
(`Scripts/check-offline.sh` — the app must work with no network by default).

## Layout

`Sources/AgentMeterCore` — **core layer**, no AppKit/SwiftUI (high fan-in,
~1 outbound). Pure parsing/pricing/formatting; the only thing tested.
`Sources/AgentMeter` — the menu-bar app (UI, networking, settings).
`Tests/AgentMeterCoreTests` — covers Core only.
`Scripts/` — bundle/release/icns/statusline/offline-check shell + swift.

## Core (`AgentMeterCore`) — the pieces that matter

- `CodexReader`, `ClaudeCodeReader`, `ClaudeStatusReader` — parse each
  agent's local logs. `CodexReader.read` is the hottest symbol (fan-in 18);
  `read`/`history` are the reader entry points.
- `UsageReader` / `UsageModels` / `UsageHistory` — the usage data model.
- `Pricing.costEstimate` — token → cost (fan-in 8). `ModelIdentity`,
  `ModelContextWindow` — model id → context window / identity.
- `StatusLevel.forUsed` — maps usage fraction to a band (normal/warning/low/
  empty); drives gauge color.
- `DateWindows` (`isToday`, `isInRollingWindow`) — rolling/daily windows.
- `CoreSupport.parseISOTimestamp`, `NumberFormatting`, `HexColor` — helpers.
- `Credentials` — parses `ClaudeCredentials` / `ServiceAccount` payloads.

## App (`AgentMeter`)

- `AgentMeterApp` — `applicationDidFinishLaunching`, menu-bar setup.
- `UsageStore.refreshNow` — refresh loop feeding the UI (fan-in 5).
- `MenuBarMetric` / `MenuBarIconPath` / `MeterBar` — menu-bar gauge drawing.
- `MenuContentView`, `SettingsView`, `Stats/*` — popover, settings, stats window.
- `Floating/*` — optional floating HUD panel.
- `Network/*` — `CodexQuotaClient`, `CodexTokenRefresher`, `NetworkOptIn`.
  All network is **opt-in**; default is offline (enforced by CI).
- `Localization.LanguageStore.tr` — string lookup (fan-in 12); UI is localized.

## Conventions

- Keep `AgentMeterCore` UI-free — it's meant to lift into a Stats module
  unchanged (see `Package.swift` comment). Don't import AppKit/SwiftUI there.
- New logic lands in Core with a test in `AgentMeterCoreTests`.
- Offline-by-default: anything touching the network goes through `NetworkOptIn`.