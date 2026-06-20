# AgentMeter

[![Latest release](https://img.shields.io/github/v/release/TeaLance/AgentMeter?sort=semver)](https://github.com/TeaLance/AgentMeter/releases/latest)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
[![License: MIT](https://img.shields.io/github/license/TeaLance/AgentMeter)](LICENSE)

在 macOS 選單列即時看到 **Claude Code** 與 **OpenAI Codex** 的用量——context window 使用率、訂閱額度（5 小時／每週）、今日 token 與訊息數。資料全部讀本機檔案，**不需要 API key、不連網**。

```
 CC 231K  5h 62%  7d 16%          ← 選單列直接顯示你選的指標
 ┌──────────────────────────────┐
 │ Claude Code                ●  │
 │   Context window  289k/1.0M 29%│
 │   ▕███▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▏        │
 │   5-hour limit         39% · 2h│
 │   Weekly              14% · 4d │
 │   今日 2.4M   訊息 542          │
 │ Codex                      ●  │
 │   今日 …                       │
 └──────────────────────────────┘
```

## 安裝

```bash
brew install --cask TeaLance/tap/agentmeter
```

或**不用終端機**：到 [Releases 頁](https://github.com/TeaLance/AgentMeter/releases/latest) 下載 `AgentMeter-x.y.z.zip` → 解壓縮 → 把 `AgentMeter.app` 拖進「應用程式」。已經過 Apple 公證，雙擊直接開、不跳警告。

需求：macOS 14 (Sonoma) 以上。

## 功能

- 選單列可**自選多個指標**並排顯示，不用點開就看得到
- Claude Code 與 Codex 的今日 token、訊息數、context window 使用率
- 真實的 **5 小時／每週訂閱額度 %** 與 reset 時間（到「設定 → 即時額度」啟用一次即可）
- 可調更新頻率、開機自動啟動

## 隱私

**預設完全離線**：只讀取本機 `~/.claude` 與 `~/.codex` 的用量紀錄來統計，**不連網、不讀 Keychain、不傳送任何資料**。

少數**選用功能**才會多做事，且**每項開啟前都會先詢問**、預設關閉：
- **顯示登入帳號**：讀取本機登入憑證「檔案」(仍**不讀 Keychain**)以顯示登入的帳號與方案；不連網。
- **Codex 即時額度**：用本機憑證的權杖連線 OpenAI 取得真實 5h／每週額度;**只有開啟此功能時才連網**。

## 授權

[MIT](LICENSE) © TeaLance
