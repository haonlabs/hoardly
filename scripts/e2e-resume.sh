#!/bin/bash
# M1 exit check: kill -9 Hoardly mid-download, relaunch, and require a byte-identical file.
# usage: scripts/e2e-resume.sh [size_mb=1024] [extra range_server.py flags, e.g. --drop 3000000]
set -euo pipefail
cd "$(dirname "$0")/.."
SIZE_MB=${1:-1024}; shift || true
APP=build/DerivedData/Build/Products/Debug/Hoardly.app
STORE="$HOME/Library/Application Support/Hoardly/downloads.json"
WORK=$(mktemp -d)
mkdir -p "$WORK/src" "$WORK/out"

xcodebuild -project Hoardly.xcodeproj -scheme Hoardly -derivedDataPath build/DerivedData build -quiet
pkill -x Hoardly || true
[ -f "$STORE" ] && mv "$STORE" "$WORK/store-backup.json"
cleanup() {
  pkill -9 -x Hoardly || true
  kill "$SERVER" 2>/dev/null || true
  defaults delete id.haonlabs.hoardly downloadDirectory 2>/dev/null || true
  defaults delete id.haonlabs.hoardly confirmBrowserDownloads 2>/dev/null || true
  defaults delete id.haonlabs.hoardly organizeByCategory 2>/dev/null || true
  rm -f "$STORE"; [ -f "$WORK/store-backup.json" ] && mv "$WORK/store-backup.json" "$STORE"
  rm -rf "$WORK"
}
trap cleanup EXIT

dd if=/dev/urandom of="$WORK/src/blob.bin" bs=1m count="$SIZE_MB" status=none
python3 scripts/range_server.py "$WORK/src" --rate 6000000 "$@" & SERVER=$!
defaults write id.haonlabs.hoardly downloadDirectory "$WORK/out"
defaults write id.haonlabs.hoardly confirmBrowserDownloads -bool false # start without the New Download panel
defaults write id.haonlabs.hoardly organizeByCategory -bool false

launch() { open "$APP"; for _ in $(seq 50); do nc -z 127.0.0.1 47801 2>/dev/null && return; sleep 0.2; done; echo "app didn't start"; exit 1; }
field() { python3 -c "
import json,sys; d=json.load(open(sys.argv[1]))[0]
r=sum(s['received'] for s in d['segments']); t=d.get('totalBytes') or 0
print({'pct': int(100*r/t) if t else 0, 'state': list(d['state'])[0], 'segments': len(d['segments'])}[sys.argv[2]])" "$STORE" "$1" 2>/dev/null || echo 0; }

launch
curl -sf -X POST http://127.0.0.1:47801/add -H "X-Hoardly-Token: $(defaults read id.haonlabs.hoardly bridgeToken)" \
  -d '{"url":"http://127.0.0.1:8765/blob.bin"}' >/dev/null
until [ "$(field pct)" -ge 50 ]; do [ "$(field state)" = failed ] && { echo "FAIL: download failed"; exit 1; }; sleep 0.2; done
pkill -9 -x Hoardly
echo "killed at $(field pct)% with $(field segments) segments"

START=$(date +%s)
launch
until [ "$(field state)" = completed ]; do
  case "$(field state)" in failed) echo "FAIL: download failed"; exit 1;; esac
  [ $(( $(date +%s) - START )) -gt 600 ] && { echo "FAIL: timeout"; exit 1; }
  sleep 0.5
done
SRC=$(shasum -a 256 "$WORK/src/blob.bin" | cut -d' ' -f1)
OUT=$(shasum -a 256 "$WORK/out/blob.bin" | cut -d' ' -f1)
[ "$SRC" = "$OUT" ] && echo "PASS: resumed after kill -9, sha256 $SRC" || { echo "FAIL: sha256 $SRC != $OUT"; exit 1; }
xattr -p com.apple.quarantine "$WORK/out/blob.bin" >/dev/null && echo "PASS: quarantine set"
