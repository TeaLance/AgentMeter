# AgentMeter

A lightweight macOS **menu-bar app** that shows your **Claude Code** and **OpenAI Codex** usage at a glance — today's token usage, message count, and a rolling-5h estimate — read entirely from local files. No API key, no network.

```
 ⊙ 2.4M        ← menu-bar item (combined "billable" tokens used today)
 ┌─────────────────────────────┐
 │ AgentMeter                  │
 │ Claude Code            ●    │
 │   2.4M  今日 tokens          │
 │   輸入 / 輸出 / 快取寫 / 快取讀  │
 │   訊息 542   近 5h（估計）2.4M │
 │ Codex                  ●    │
 │   0  今日 tokens             │
 │ 最後更新 22:50   [立即更新][設定][結束] │
 └─────────────────────────────┘
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 14+ / Swift 5.9+ to build

## Build & run

```bash
# Build a double-clickable .app (menu-bar agent, no Dock icon)
bash Scripts/bundle.sh
open dist/AgentMeter.app
```

Other options:

```bash
swift run              # run straight from the package (dev)
swift test             # run the parsing-layer unit tests
open Package.swift     # open in Xcode for GUI debugging
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

## Settings

- Refresh interval (15s / 30s / 1m / 5m)
- What the menu-bar text shows (combined / Claude only / Codex only)
- Show/hide each tool
- Launch at login (via `SMAppService`)

## Why "近 5h（估計）" is an estimate

Neither tool persists your subscription's real rate-limit cap to disk, so a true
"% remaining" can't be computed locally. AgentMeter instead shows the tokens used in
the **last 5 hours** as a rough proxy, and labels it as an estimate.

## Privacy

AgentMeter only **reads** files under `~/.claude` and `~/.codex` on your machine. It makes
no network requests and sends nothing anywhere. It is **not sandboxed** (it needs to read
those home-directory paths), so it isn't distributed via the Mac App Store.

## Tests

```bash
swift test
```

The `AgentMeterCore` parsing/aggregation logic is covered by unit tests (date windowing,
de-duplication, Codex delta summing, malformed-line handling, missing-directory handling,
compact number formatting).

## Project layout

```
Sources/AgentMeterCore/   reusable parsing layer (no UI)
Sources/AgentMeter/       SwiftUI MenuBarExtra app
Tests/AgentMeterCoreTests/ unit tests + synthetic fixtures
Scripts/bundle.sh         wrap the binary into AgentMeter.app
```

## Relation to Stats

This started as an idea to add a usage module to [exelban/Stats](https://github.com/exelban/stats),
but Stats is scoped to hardware/system monitoring, so an app-usage module is out of scope
there. AgentMeter is a standalone tool instead. If a Stats module is ever pursued, the
`AgentMeterCore` reader layer can be lifted in as-is; only the UI/settings would be rewritten
against Stats' module API.
