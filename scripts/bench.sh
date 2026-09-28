#!/bin/bash
# Time one download with curl (single connection) vs Hoardly, and check both files match.
# usage: scripts/bench.sh URL
set -euo pipefail
cd "$(dirname "$0")/.."
URL=$1
APP=build/DerivedData/Build/Products/Debug/Hoardly.app
STORE="$HOME/Library/Application Support/Hoardly/downloads.json"
WORK=$(mktemp -d)
now() { python3 -c 'import time; print(time.time())'; }

pkill -x Hoardly || true
[ -f "$STORE" ] && mv "$STORE" "$WORK/store-backup.json"
cleanup() {
  pkill -x Hoardly || true
  defaults delete id.haonlabs.hoardly downloadDirectory 2>/dev/null || true
  defaults delete id.haonlabs.hoardly confirmBrowserDownloads 2>/dev/null || true
  defaults delete id.haonlabs.hoardly organizeByCategory 2>/dev/null || true
  rm -f "$STORE"; [ -f "$WORK/store-backup.json" ] && mv "$WORK/store-backup.json" "$STORE"
  rm -rf "$WORK"
}
trap cleanup EXIT

T0=$(now); curl -sfL -o "$WORK/curl.bin" "$URL"; T1=$(now)
defaults write id.haonlabs.hoardly downloadDirectory "$WORK/out"
defaults write id.haonlabs.hoardly confirmBrowserDownloads -bool false # start without the New Download panel
defaults write id.haonlabs.hoardly organizeByCategory -bool false
open "$APP"; until nc -z 127.0.0.1 47801 2>/dev/null; do sleep 0.2; done
T2=$(now)
curl -sf -X POST http://127.0.0.1:47801/add -H "X-Hoardly-Token: $(defaults read id.haonlabs.hoardly bridgeToken)" -d "{\"url\":\"$URL\"}" >/dev/null
state() { python3 -c "import json,sys; print(list(json.load(open(sys.argv[1]))[0]['state'])[0])" "$STORE" 2>/dev/null || echo queued; }
until [[ "$(state)" =~ completed|failed ]]; do sleep 0.3; done
T3=$(now)
python3 -c "
import json,sys; d=json.load(open(sys.argv[1]))[0]
print('Hoardly:', d['state'], len(d['segments']), 'segments')" "$STORE"
python3 -c "c=$T1-$T0; h=$T3-$T2; print(f'curl {c:.1f}s   Hoardly {h:.1f}s   speedup {c/h:.2f}x')"
[ "$(shasum -a 256 < "$WORK/curl.bin")" = "$(shasum -a 256 < "$WORK/out/"*)" ] && echo "PASS: identical" || echo "FAIL: files differ"
