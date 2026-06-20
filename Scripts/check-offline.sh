#!/usr/bin/env bash
# Verifiable "offline by default" guarantee: no networking outside Sources/AgentMeter/Network/.
# AgentMeterCore must never touch the network at all.
set -euo pipefail
cd "$(dirname "$0")/.."

pattern='URLSession|NWConnection|NWBrowser|import Network|CFSocketRef|getaddrinfo'

# Anything under Network/ is allowed; everything else (incl. all of AgentMeterCore) is not.
hits=$(grep -rnE "$pattern" Sources \
  | grep -v '/Network/' || true)

if [[ -n "$hits" ]]; then
  echo "❌ offline check FAILED — networking found outside Sources/AgentMeter/Network/:"
  echo "$hits"
  exit 1
fi

echo "✅ offline check passed — no networking outside Sources/AgentMeter/Network/"
