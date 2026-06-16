# AgentMeter

[![Latest release](https://img.shields.io/github/v/release/TeaLance/AgentMeter?sort=semver)](https://github.com/TeaLance/AgentMeter/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/TeaLance/AgentMeter/total)](https://github.com/TeaLance/AgentMeter/releases)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
[![License: MIT](https://img.shields.io/github/license/TeaLance/AgentMeter)](LICENSE)
[![gitleaks](https://img.shields.io/badge/protected%20by-gitleaks-blue)](https://github.com/gitleaks/gitleaks-action)

一個輕量的 macOS **選單列 App**，一眼看到 **Claude Code** 與 **OpenAI Codex** 的用量——context window 使用率、訂閱額度、今日 token 與訊息數——用 `/usage` 那種條狀呈現，全部讀本機檔案。**不需要 API key、不連網。**

```
 CC 231K  5h 62%  7d 16%   ← 選單列直接顯示你勾選的指標（見下方）
 ┌──────────────────────────────────────┐
 │ AgentMeter                            │
 │ Claude Code                       ●   │
 │   Context window      289k / 1.0M (29%)│
 │   ▕███▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   5-hour limit              39% · 2h  │   ← 啟用橋接後顯示真實值
 │   ▕███████▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   Weekly · all models       14% · 4d  │
 │   ▕███▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏             │
 │   今日 tokens 2.4M   訊息 542   近5h 2.4M│
 │ Codex                             ●   │
 │   Context window      …                │
 │ 最後更新 22:50  [立即更新][設定…][結束]   │
 └──────────────────────────────────────┘
```

## 安裝

```bash
brew install --cask TeaLance/tap/agentmeter
```

這個 cask 會把**已簽章且公證**的 `AgentMeter.app` 裝到 `/Applications`，所以開啟時**不會跳 Gatekeeper 警告**。從 Spotlight／應用程式啟動即可，它常駐在選單列。更新用 `brew upgrade --cask agentmeter`。

**不想用終端機？** 到 [**Releases 頁**](https://github.com/TeaLance/AgentMeter/releases/latest) 下載最新的 `AgentMeter-x.y.z.zip`，解壓縮後把 `AgentMeter.app` 拖進 `/Applications`。因為已公證，直接雙擊就能開——不用右鍵「打開」那一套。

需求：macOS 14 (Sonoma) 以上。Universal（Apple Silicon + Intel 皆可）。

## 從原始碼建置

```bash
bash Scripts/bundle.sh   # 建出可雙擊的 .app（選單列 App、無 Dock 圖示）
open dist/AgentMeter.app

# 開發用：
swift run                # 直接從 package 執行
swift test               # 跑解析層的單元測試
open Package.swift       # 用 Xcode 開啟做 GUI 除錯
```

## 運作原理

解析層 `AgentMeterCore` 是純 Swift、不含 UI，可被重用（例如未來移植成 Stats 模組）。它讀兩個本機資料來源：

| 工具 | 來源 | Token | 訊息數 |
|------|--------|--------|----------|
| Claude Code | `~/.claude/projects/**/*.jsonl` | 每筆訊息的 `message.usage` | 今日的 assistant 行數 |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `token_count` 事件的 `last_token_usage` | 今日的 `agent_message` 事件數 |

幾個關鍵細節：

- **去重（Claude Code）**：續接的 session 會重寫先前的行，所以用 `(message.id, requestId)` 去重——跟 [`ccusage`](https://github.com/ryoppippi/ccusage) 同樣作法。
- **逐回合增量（Codex）**：`total_token_usage` 是該 session 累計值，所以當日量改用每回合的 `last_token_usage` 增量相加。
- **「可計費」headline**：選單列數字與每區的大數字用 `input + output + cacheCreation + reasoning`，**排除快取讀取（cache reads）**。快取讀取是便宜的重讀、量常破百萬，會把數字灌爆；完整明細（含快取讀取）在下拉面板裡看得到。
- **時間視窗**：時間戳是 UTC；「今日」與滾動視窗都以你的**本機時區**判斷。
- **Context window**：取最近一個 session 的最後一回合。transcript 記錄的 model id **不含** `[1m]` 後綴，所以用量超過 200k 就判定為 1M 視窗的 session；Codex 則直接提供 `model_context_window`。

## 真實訂閱額度（5h／每週那兩條）

`39% · resets 2h` 這種真實數字**不在任何本機檔案**——Claude Code 只把它透過 **statusLine 指令** 用 JSON 傳出去。AgentMeter 內建一個小橋接，把那包資料的快照存到 `~/.claude/agentmeter-status.json`（**不連網、不碰 Keychain**）。

到 **設定 → 即時額度** 啟用。它會先備份 `~/.claude/settings.json`、安裝 `~/.claude/agentmeter-statusline.sh`、並把 `statusLine` 指向它。接著在 Claude Code 送出一則訊息，`5-hour limit` / `Weekly` 兩條就會出現真實百分比與 reset 時間。若你已有自訂的 statusLine，AgentMeter **不會覆蓋**它。關掉開關即還原。在啟用之前，會改顯示本機的 **「近 5h（估計）」**（過去 5 小時用量，不是真實上限）。

## 選單列多指標

選單列會把你勾選的指標**並排顯示**，不必點開下拉——例如 `CC 231K  5h 62%  7d 16%  Σ 231K`。到 **設定 → 選單列顯示內容（可多選）** 勾選：今日 token、5h %、每週 %、context %、訊息數——Claude、Codex、或合計都可以。規則：

- 沒資料的項目會**自動隱藏**（例如還沒啟用橋接時的 5h／每週，或今天沒用的 Codex）。全部都隱藏時會顯示一個 gauge 小圖示。
- 只有當**同一種**指標同時顯示兩個工具時，才會加 `CC` / `CX` 前綴來區分。5h／每週是 Claude 專屬，永不加前綴。

## 設定

- 選單列顯示內容（多選，見上方）
- 更新頻率（15s / 30s / 1m / 5m）
- 下拉面板要顯示哪些工具
- 開機自動啟動（透過 `SMAppService`）
- 透過 statusLine 橋接顯示真實訂閱額度（見上方）

## 隱私

AgentMeter 只**讀取**你電腦上 `~/.claude` 與 `~/.codex` 底下的檔案。它**不發任何網路請求、不讀 Keychain、不把任何東西傳出去**。statusLine 橋接只是把 Claude Code 本來就會交給 status-line 指令的 JSON 存成檔案。這個 App **沒有啟用沙盒**（它需要讀那些家目錄路徑），因此不透過 Mac App Store 發佈。

## 測試

```bash
swift test
```

`AgentMeterCore` 的解析／聚合邏輯都有單元測試覆蓋（時間視窗、去重、Codex 增量加總、context window 偵測、status 檔解析、壞行處理、缺目錄處理、數字緊湊格式化）。

## 專案結構

```
Sources/AgentMeterCore/        可重用的解析層（無 UI）
  ClaudeCodeReader / CodexReader / ClaudeStatusReader / ModelContextWindow / UsageModels …
Sources/AgentMeter/            SwiftUI MenuBarExtra App
  MenuContentView / MeterBar / SettingsView / StatusLineBridge / UsageStore …
Tests/AgentMeterCoreTests/     單元測試 + 合成 fixtures
Scripts/bundle.sh              把執行檔包成 AgentMeter.app
Scripts/agentmeter-statusline.sh  statusLine 橋接腳本
```

## 與 Stats 的關係

這個專案的起點，是想替 [exelban/Stats](https://github.com/exelban/stats) 加一個用量模組；但 Stats 的範疇限定在硬體／系統監控，應用層的「AI 用量」落在範疇外。所以 AgentMeter 改做成獨立工具。若日後真的要做 Stats 模組，`AgentMeterCore` 解析層可以原封不動搬過去，只需依 Stats 的模組 API 重寫 UI 與設定。

## 發佈（維護者）

Homebrew cask 提供的是**已簽章 + 公證**的版本，這正是「開啟不跳警告」的關鍵。一次性設定（需要付費的 Apple Developer 帳號）：

1. **Developer ID 憑證**——最穩的做法是用「鑰匙圈存取 → 憑證輔助程式 → 從憑證授權要求憑證」產生 CSR（私鑰才會生在本機），再到 [developer.apple.com](https://developer.apple.com) → Certificates → `+` → **Developer ID Application** 上傳 CSR、下載 `.cer` 雙擊匯入。用 `security find-identity -v -p codesigning` 確認。
2. **公證憑證**——到 appleid.apple.com 產生 App 專用密碼，然後：
   ```bash
   xcrun notarytool store-credentials AgentMeter-notary \
     --apple-id <你的 Apple ID> --team-id <TEAMID> --password <App 專用密碼>
   ```

接著發佈：

```bash
Scripts/release.sh 0.1.0          # 通用建置 → 簽章 → 公證 → staple → zip + sha256
gh release create v0.1.0 dist/AgentMeter-0.1.0.zip --title v0.1.0 --notes "…"
```

最後把 [TeaLance/homebrew-tap](https://github.com/TeaLance/homebrew-tap) 的 `Casks/agentmeter.rb` 裡的 `version` 與 `sha256` 更新（`release.sh` 結尾會印出 sha256）。

## 授權

[MIT](LICENSE) © TeaLance
