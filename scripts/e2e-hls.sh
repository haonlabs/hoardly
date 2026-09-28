#!/bin/bash
# M5 check: HLS → .mp4 for MPEG-TS, AES-128 TS, and fMP4 with separate audio; DRM and live refused.
# Fixtures are 3-segment cuts of Apple's public test streams (needs internet).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/DerivedData/Build/Products/Debug/Hoardly.app
STORE="$HOME/Library/Application Support/Hoardly/downloads.json"
WORK=$(mktemp -d); SITE="$WORK/site"; mkdir -p "$SITE" "$WORK/out"
APPLE=https://devstreaming-cdn.apple.com/videos/streaming/examples

# MPEG-TS, muxed audio: local copies of 3 segments.
{ echo '#EXTM3U'; echo '#EXT-X-TARGETDURATION:10'; } > "$SITE/ts.m3u8"
for i in 0 1 2; do
  curl -sf -o "$SITE/seg$i.ts" "$APPLE/bipbop_4x3/gear1/fileSequence$i.ts"
  printf '#EXTINF:10,\nseg%s.ts\n' $i >> "$SITE/ts.m3u8"
done
echo '#EXT-X-ENDLIST' >> "$SITE/ts.m3u8"

# Same segments, AES-128-CBC: one with an explicit IV, the others using the media sequence number.
KEY=000102030405060708090a0b0c0d0e0f; IV=0f0e0d0c0b0a09080706050403020100
printf "$(echo $KEY | sed 's/../\\x&/g')" > "$SITE/key.bin"
{ echo '#EXTM3U'; echo '#EXT-X-MEDIA-SEQUENCE:0'; echo "#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\",IV=0x$IV"; } > "$SITE/aes.m3u8"
openssl enc -aes-128-cbc -K $KEY -iv $IV -in "$SITE/seg0.ts" -out "$SITE/enc0.ts"
printf '#EXTINF:10,\nenc0.ts\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n' >> "$SITE/aes.m3u8"
for i in 1 2; do
  openssl enc -aes-128-cbc -K $KEY -iv "$(printf '%032x' $i)" -in "$SITE/seg$i.ts" -out "$SITE/enc$i.ts"
  printf '#EXTINF:10,\nenc%s.ts\n' $i >> "$SITE/aes.m3u8"
done
echo '#EXT-X-ENDLIST' >> "$SITE/aes.m3u8"

# fMP4 with byte ranges + init section, audio as a separate rendition: first 3 segments, remote media.
FMP4=$APPLE/img_bipbop_adv_example_fmp4
cut3() { # playlist base → header, first 3 segments, absolute URIs
  curl -sf "$1/prog_index.m3u8" | awk -v base="$1/" '
    /^#EXT-X-MAP/ { sub(/URI="/, "URI=\"" base) }
    /^#EXTINF/ { n++ } n > 3 { exit }
    /^[^#]/ { $0 = base $0 }
    { print } END { print "#EXT-X-ENDLIST" }'
}
cut3 "$FMP4/v2" > "$SITE/video.m3u8"
cut3 "$FMP4/a1" > "$SITE/audio.m3u8"
cat > "$SITE/fmp4.m3u8" <<M3U
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",DEFAULT=YES,URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2177116,RESOLUTION=960x540,AUDIO="aud1"
video.m3u8
M3U

# Must be refused.
printf '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"\n#EXTINF:10,\nseg0.ts\n#EXT-X-ENDLIST\n' > "$SITE/drm.m3u8"
printf '#EXTM3U\n#EXTINF:10,\nseg0.ts\n' > "$SITE/live.m3u8"

xcodebuild -project Hoardly.xcodeproj -scheme Hoardly -derivedDataPath build/DerivedData build -quiet
python3 scripts/range_server.py "$SITE" --port 8769 & SERVER=$!
pkill -x Hoardly || true
[ -f "$STORE" ] && mv "$STORE" "$WORK/store-backup.json"
cleanup() {
  pkill -x Hoardly || true; kill "$SERVER" 2>/dev/null || true
  for k in downloadDirectory confirmBrowserDownloads organizeByCategory; do defaults delete id.haonlabs.hoardly $k 2>/dev/null || true; done
  rm -f "$STORE"; [ -f "$WORK/store-backup.json" ] && mv "$WORK/store-backup.json" "$STORE"
  rm -rf "$WORK"
}
trap cleanup EXIT
defaults write id.haonlabs.hoardly downloadDirectory "$WORK/out"
defaults write id.haonlabs.hoardly confirmBrowserDownloads -bool false
defaults write id.haonlabs.hoardly organizeByCategory -bool false
open "$APP"; until nc -z 127.0.0.1 47801 2>/dev/null; do sleep 0.2; done
items=$(for n in ts aes fmp4 drm live; do printf '{"url":"http://127.0.0.1:8769/%s.m3u8","filename":"%s"},' $n $n; done)
curl -sf -X POST http://127.0.0.1:47801/add -H "X-Hoardly-Token: $(defaults read id.haonlabs.hoardly bridgeToken)" \
  -d "{\"items\":[${items%,}]}" >/dev/null

state() { python3 -c "
import json,sys
for d in json.load(open(sys.argv[1])):
  if d['fileName'].startswith(sys.argv[2]+'.'): s=d['state']; k=list(s)[0]; print(k, s[k].get('_0','') if isinstance(s[k],dict) else '')" "$STORE" "$1" 2>/dev/null; }
for _ in $(seq 240); do
  pending=0; for n in ts aes fmp4 drm live; do [[ "$(state $n)" =~ ^(completed|failed) ]] || pending=1; done
  [ $pending = 0 ] && break; sleep 0.5
done

FAIL=0
for n in ts aes fmp4; do
  probe=$(swift scripts/probe-media.swift "$WORK/out/$n.mp4" 2>/dev/null || echo "unreadable ($(state $n))")
  if [[ "$probe" =~ duration=(29|30|18)\ tracks=soun,vide\ frame=ok ]]; then echo "PASS: $n.mp4 $probe"; else echo "FAIL: $n.mp4 $probe"; FAIL=1; fi
done
[[ "$(state drm)" == "failed This stream is DRM-protected"* ]] && echo "PASS: DRM refused" || { echo "FAIL: drm → $(state drm)"; FAIL=1; }
[[ "$(state live)" == "failed Live streams"* ]] && echo "PASS: live refused" || { echo "FAIL: live → $(state live)"; FAIL=1; }
exit $FAIL
