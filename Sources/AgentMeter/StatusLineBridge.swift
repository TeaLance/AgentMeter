import Foundation

/// Manages the Claude Code statusLine bridge that feeds real subscription
/// rate-limit data to AgentMeter. Enabling it installs a small script and points
/// `~/.claude/settings.json`'s `statusLine` at it (after backing the file up).
enum BridgeState: Equatable {
    case enabled
    case disabled
    case conflict   // a different statusLine is already configured — we won't clobber it
}

enum BridgeError: LocalizedError {
    case conflict

    var errorDescription: String? {
        switch self {
        case .conflict:
            return "你已經設定了自己的 statusLine。為了不覆蓋它，請手動整合，或先移除既有設定。"
        }
    }
}

struct StatusLineBridge {
    static let shared = StatusLineBridge()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var claudeDir: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    private var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }
    private var scriptURL: URL { claudeDir.appendingPathComponent("agentmeter-statusline.sh") }
    private var statusURL: URL { claudeDir.appendingPathComponent("agentmeter-status.json") }
    private var backupURL: URL { claudeDir.appendingPathComponent("settings.json.agentmeter.bak") }

    // MARK: State

    func state() -> BridgeState {
        guard let settings = readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any] else {
            return .disabled
        }
        if (statusLine["command"] as? String) == scriptURL.path {
            return .enabled
        }
        return .conflict
    }

    // MARK: Enable / disable

    func enable() throws {
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        var settings = readSettings() ?? [:]
        if let existing = settings["statusLine"] as? [String: Any],
           (existing["command"] as? String) != scriptURL.path {
            throw BridgeError.conflict
        }

        try installScript()

        // Back up the original settings before modifying.
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        }

        settings["statusLine"] = [
            "type": "command",
            "command": scriptURL.path,
            "padding": 0,
        ]
        try writeSettings(settings)
    }

    func disable() throws {
        if var settings = readSettings(),
           let statusLine = settings["statusLine"] as? [String: Any],
           (statusLine["command"] as? String) == scriptURL.path {
            settings.removeValue(forKey: "statusLine")
            try writeSettings(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: statusURL)
    }

    // MARK: Helpers

    private func installScript() throws {
        try StatusLineBridge.scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    /// The bridge script. Kept in sync with Scripts/agentmeter-statusline.sh.
    /// Code is passed via `python3 -c` so stdin stays free for the piped JSON.
    static let scriptBody = #"""
    #!/usr/bin/env bash
    # AgentMeter statusLine bridge — persists the rate-limit snapshot Claude Code
    # passes to statusLine commands, and prints a compact line. No network/Keychain.
    OUT="$HOME/.claude/agentmeter-status.json"
    python3 -c '
    import sys, json, os, tempfile, datetime
    out_path = sys.argv[1]
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    rl = data.get("rate_limits")
    model = data.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or ""
    snapshot = {
        "asOf": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "model": model_name,
        "rate_limits": rl,
        "context_window": data.get("context_window"),
    }
    try:
        d = os.path.dirname(out_path) or "."
        fd, tmp = tempfile.mkstemp(dir=d)
        with os.fdopen(fd, "w") as f:
            json.dump(snapshot, f)
        os.replace(tmp, out_path)
    except Exception:
        pass
    line = model_name or "Claude"
    if isinstance(rl, dict):
        fh = (rl.get("five_hour") or {}).get("used_percentage")
        if fh is not None:
            line += "  5h %.0f%%" % fh
        wk = (rl.get("seven_day") or {}).get("used_percentage")
        if wk is not None:
            line += "  7d %.0f%%" % wk
    print(line)
    ' "$OUT"
    """#
}
