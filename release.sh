#!/bin/sh
# Publie une version : ./release.sh 0.2.0 "Notes"
# Exporte le .pck (mise à jour légère) + le zip Linux, puis crée la release GitHub.
set -e
V="$1"; NOTES="${2:-Version $1}"
[ -n "$V" ] || { echo "usage: $0 <version> [notes]"; exit 1; }
cd "$(dirname "$0")"
REPO=goodview-software/goodview-launcher
GODOT="flatpak run org.godotengine.Godot"
ENGINE="$($GODOT --version | cut -d. -f1-3)"
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT" build/linux

sed -i "s/^const VERSION := .*/const VERSION := \"$V\"/" version.gd
$GODOT --headless --path . --export-pack "Linux" "$OUT/goodview-launcher-$V.pck"
$GODOT --headless --path . --export-release "Linux" build/linux/GoodviewLauncher.x86_64
$GODOT --headless --path . --export-debug "Android" "$OUT/GoodviewLauncher.apk" || echo "APK non généré"
cp icon.svg build/linux/
rm -rf build/GoodviewLauncher && cp -r build/linux build/GoodviewLauncher
(cd build && zip -qr "release/GoodviewLauncher-$V-linux.zip" GoodviewLauncher) && rm -rf build/GoodviewLauncher
cp "$OUT/GoodviewLauncher-$V-linux.zip" "$OUT/GoodviewLauncher-linux.zip"

rm -f "$OUT"/*.idsig
SHA="$(sha256sum "$OUT/goodview-launcher-$V.pck" | cut -d' ' -f1)"
cat > "$OUT/version.json" <<J
{"version": "$V", "godot": "$ENGINE", "sha256": "$SHA",
 "pck": "https://github.com/$REPO/releases/download/v$V/goodview-launcher-$V.pck"}
J

git add -A && git commit -qm "Version $V" || true
git tag -f "v$V" && git push -q origin HEAD && git push -qf origin "v$V"
gh release create "v$V" --repo "$REPO" --title "Goodview Launcher $V" --notes "$NOTES" "$OUT"/*
echo "Publié : https://github.com/$REPO/releases/tag/v$V"
