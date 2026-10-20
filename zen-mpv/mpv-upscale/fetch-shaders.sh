#!/usr/bin/env bash
# Downloads the upscaler shaders into ~/.config/mpv-upscale/shaders (not stored in git: ~15 MB). Re-run to refresh. Skips files already present.
# Sources: Arch package mpv-shim-default-shaders (ArtCNN, Anime4K, FSRCNNX, FSR, NVScaler/NVSharpen, CAS, KrigBilateral, nnedi3),
# bjin/mpv-prescalers (RAVU), igv gists (SSimSuperRes).
set -euo pipefail
OUT="$HOME/.config/mpv-upscale/shaders"; mkdir -p "$OUT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if [ ! -f "$OUT/ArtCNN_C4F32.glsl" ]; then
  url="$(pacman -Sp mpv-shim-default-shaders 2>/dev/null | tail -1)"
  curl -fsSL -m 300 -o "$TMP/p.pkg.tar.zst" "$url"
  bsdtar -xf "$TMP/p.pkg.tar.zst" -C "$TMP" usr/share/mpv-shim-default-shaders/shaders
  cp -n "$TMP"/usr/share/mpv-shim-default-shaders/shaders/* "$OUT/"
fi
for f in ravu-lite-r4 ravu-r4 ravu-zoom-r3; do
  [ -f "$OUT/$f.hook" ] || curl -fsSL -m 120 -o "$OUT/$f.hook" "https://raw.githubusercontent.com/bjin/mpv-prescalers/master/$f.hook"
done
[ -f "$OUT/SSimSuperRes.glsl" ] || curl -fsSL -m 60 -o "$OUT/SSimSuperRes.glsl" "https://gist.githubusercontent.com/igv/2364ffa6e81540f29cb7ab4c9bc05b6b/raw/SSimSuperRes.glsl"
echo "shaders: $(ls "$OUT" | wc -l) files in $OUT"
