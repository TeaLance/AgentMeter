# AgentMeter

[![Latest release](https://img.shields.io/github/v/release/TeaLance/AgentMeter?sort=semver)](https://github.com/TeaLance/AgentMeter/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/TeaLance/AgentMeter/total)](https://github.com/TeaLance/AgentMeter/releases)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
[![License: MIT](https://img.shields.io/github/license/TeaLance/AgentMeter)](LICENSE)
[![gitleaks](https://img.shields.io/badge/protected%20by-gitleaks-blue)](https://github.com/gitleaks/gitleaks-action)

A lightweight macOS **menu-bar app** that shows your **Claude Code** and **OpenAI Codex**
usage at a glance — context-window fill, subscription limits, today's tokens and message
count — in `/usage`-style bars, read from local files. No API key, no network.

```
 CC 231K  5h 62%  7d 16%   ← menu-bar item shows the metrics you pick (see below)
 ┌──────────────────────────────────────┐
 │ AgentMeter                            │
 │ Claude Code                       ●   │
 │   Context window      289k / 1.0M (29%)│
 │   ▕███▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   5-hour limit              39% · 2h  │   ← real, when the bridge is on
 │   ▕███████▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   Weekly · all models       14% · 4d  │
 │   ▕███▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   今日 tokens 2.4M   訊息 542   近5h 2.4M│
 │ Codex                             ●   │
 │   Context window      …                │
 │ 最後更新 22:50  [立即更新][設定…][結束]   │
 └──────────────────────────────────────┘
```

## Install

```bash
brew install --cask TeaLance/tap/agentmeter
```

The cask installs a signed & notarized `AgentMeter.app` into `/Applications`, so it
opens with no Gatekeeper prompt. Launch it from Spotlight/Applications; it lives in the
menu bar. To update: `brew upgrade --cask agentmeter`.

**Prefer not to use the terminal?** Download the latest `AgentMeter-x.y.z.zip` from the
[**Releases page**](https://github.com/TeaLance/AgentMeter/releases/latest), unzip it, and
drag `AgentMeter.app` into `/Applications`. It's notarized, so it just opens — no
right-click-to-open dance.

Requirements: macOS 14 (Sonoma) or later. Universal (Apple Silicon + Intel).

## Build from source

```bash
bash Scripts/bundle.sh   # build a double-clickable .app (menu-bar agent, no Dock icon)
open dist/AgentMeter.app

# or, for development:
swift run                # run straight from the package
swift test               # run the parsing-layer unit tests
open Package.swift       # open in Xcode for GUI debugging
```

## How it works

The parsing layer (`AgentMeterCore`) is pure Swift with no UI, so it can be reused
elsewhere (e.g. a future Stats module). It reads two local data sources:

| Tool | Source | Tokens | Messages |
|------|--------|--------|----------|
| Claude Code | `~/.claude/projects/**/*.jsonl` | per-message `message.usage` | assistant rows today |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `token_count` events' `last_token_usage` | `agent_message` events today |

Key details:

- **De-duplication (Claude Code):** resumed sessions re-write earlier rows, so usage is
  de-duplicated by `(message.id, requestId)` — the same approach [`ccusage`](https://github.com/ryoppippi/ccusage) uses.
- **Per-turn deltas (Codex):** `total_token_usage` is cumulative per session, so daily
  totals are summed from the per-turn `last_token_usage` deltas instead.
- **"Billable" headline:** the menu-bar number and each section's headline use
  `input + output + cacheCreation + reasoning` and **exclude cache *reads***. Cache reads
  are cheap re-reads of prior context and would otherwise dwarf everything (often 100M+).
  The full breakdown — including cache reads — is shown in the dropdown.
- **Time windows:** timestamps are UTC; "today" and the rolling window are evaluated in
  your local time zone.
- **Context window:** taken from the most-recent session's last turn. Transcripts record
  the model id *without* the `[1m]` tier suffix, so a context above 200k is treated as a
  1M-window session; Codex reports `model_context_window` directly.

## Real subscription limits (the 5h / weekly bars)

The true `39% · resets 2h` figures are **not** stored in any local file — Claude Code only
exposes them as JSON piped to a **statusLine command**. AgentMeter ships a tiny bridge that
captures that snapshot to `~/.claude/agentmeter-status.json` (no network, no Keychain).

Enable it from **Settings → 即時額度**. That backs up `~/.claude/settings.json`, installs
`~/.claude/agentmeter-statusline.sh`, and points `statusLine` at it. Send one message in
Claude Code and the `5-hour limit` / `Weekly` bars appear with real percentages and reset
times. If you already have a custom statusLine, AgentMeter won't overwrite it. Toggle off to
restore. Until it's enabled, AgentMeter shows the local **"近 5h（估計）"** proxy instead
(tokens used in the last 5 hours — not a real cap).

## Menu-bar item (multi-metric)

The menu-bar item shows the metrics you pick, inline, so you don't have to open the
dropdown — e.g. `CC 231K  5h 62%  7d 16%  Σ 231K`. Choose them in
**Settings → 選單列顯示內容（可多選）**: today tokens, 5h %, weekly %, context %, message
count — for Claude, Codex, or the combined total. Rules:

- Metrics with no data are auto-hidden (e.g. 5h/weekly before the bridge is on, or Codex
  when unused today). If everything is hidden, a gauge icon is shown.
- A `CC` / `CX` prefix is added only when the *same* metric is shown for both tools (so you
  can tell them apart). 5h / weekly are Claude-only and never prefixed.

## Settings

- Menu-bar contents (multi-select, above)
- Refresh interval (15s / 30s / 1m / 5m)
- Show/hide each tool in the dropdown
- Launch at login (via `SMAppService`)
- Real subscription limits via the statusLine bridge (above)

## Privacy

AgentMeter only **reads** files under `~/.claude` and `~/.codex` on your machine. It makes
no network requests, reads no Keychain, and sends nothing anywhere. The statusLine bridge
only persists the JSON Claude Code already hands to status-line commands. The app is **not
sandboxed** (it needs to read those home-directory paths), so it isn't distributed via the
Mac App Store.

## Tests

```bash
swift test
```

The `AgentMeterCore` parsing/aggregation logic is covered by unit tests (date windowing,
de-duplication, Codex delta summing, context-window detection, status-file parsing,
malformed-line handling, missing-directory handling, compact number formatting).

## Project layout

```
Sources/AgentMeterCore/        reusable parsing layer (no UI)
  ClaudeCodeReader / CodexReader / ClaudeStatusReader / ModelContextWindow / UsageModels …
Sources/AgentMeter/            SwiftUI MenuBarExtra app
  MenuContentView / MeterBar / SettingsView / StatusLineBridge / UsageStore …
Tests/AgentMeterCoreTests/     unit tests + synthetic fixtures
Scripts/bundle.sh              wrap the binary into AgentMeter.app
Scripts/agentmeter-statusline.sh  the statusLine bridge script
```

## Relation to Stats

This started as an idea to add a usage module to [exelban/Stats](https://github.com/exelban/stats),
but Stats is scoped to hardware/system monitoring, so an app-usage module is out of scope
there. AgentMeter is a standalone tool instead. If a Stats module is ever pursued, the
`AgentMeterCore` reader layer can be lifted in as-is; only the UI/settings would be rewritten
against Stats' module API.

## Releasing (maintainer)

The Homebrew cask serves a **signed + notarized** build, which is what makes it open
without a Gatekeeper prompt. One-time setup (needs a paid Apple Developer account):

1. **Developer ID certificate** — Xcode → Settings → Accounts → *Manage Certificates…* →
   `+` → **Developer ID Application**. Confirm with `security find-identity -v -p codesigning`.
2. **Notary credentials** — create an app-specific password at appleid.apple.com, then:
   ```bash
   xcrun notarytool store-credentials AgentMeter-notary \
     --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```

Then cut a release:

```bash
Scripts/release.sh 0.1.0          # universal build → sign → notarize → staple → zip + sha256
gh release create v0.1.0 dist/AgentMeter-0.1.0.zip --title v0.1.0 --notes "…"
```

Finally bump `version` + `sha256` in the tap's `Casks/agentmeter.rb`
([TeaLance/homebrew-tap](https://github.com/TeaLance/homebrew-tap)).

## License

[MIT](LICENSE) © TeaLance
