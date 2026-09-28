#!/bin/bash
# Zips extension/ for the Chrome Web Store, Microsoft Edge Add-ons and Firefox AMO (one package fits all three).
# Drops "nativeMessaging": only Safari uses it, and stores reject permissions an extension never uses.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(python3 -c 'import json; print(json.load(open("extension/manifest.json"))["version"])')
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude '.*' extension/ "$STAGE/"
python3 - "$STAGE/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]; m = json.load(open(path))
m["permissions"] = [p for p in m["permissions"] if p != "nativeMessaging"]
open(path, "w").write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
PY
mkdir -p dist
ZIP=$PWD/dist/hoardly-extension-$VERSION.zip
rm -f "$ZIP"
(cd "$STAGE" && zip -q -X -r "$ZIP" .)
echo "✔ dist/hoardly-extension-$VERSION.zip ($(unzip -l "$ZIP" | tail -1 | awk '{print $2}') files)"
