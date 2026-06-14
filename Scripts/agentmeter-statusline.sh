#!/usr/bin/env bash
# AgentMeter statusLine bridge.
# Claude Code pipes a JSON blob (including `rate_limits` for subscribers) to this
# command on stdin every status-line render. We persist the rate-limit snapshot
# for AgentMeter to read, and print a compact status line. No network, no Keychain.
# NOTE: the code is passed via `python3 -c` so stdin stays free for the JSON.
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
