#!/usr/bin/env bash
set -euo pipefail

# Keep the review runner independent of the Ubuntu font mirror.
font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/hyt-review"
mkdir -p "$font_dir"
install_font() {
  local source="$1" blob="$2" file="$font_dir/${1##*/}"
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 90 \
    "https://raw.githubusercontent.com/$source" --output "$file"
  test "$(git hash-object "$file")" = "$blob"
}
cjk='notofonts/noto-cjk/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/OTF/SimplifiedChinese'
install_font "$cjk/NotoSansCJKsc-Regular.otf" dc15562470b4f842321894787a0d066879ccff8b
install_font "$cjk/NotoSansCJKsc-Bold.otf" ff4c0450e8a5bf0290fbb6013a72dc61a10e8e56
install_font 'googlefonts/noto-emoji/22e564626297b4df0a40570ad81d6c05cc7c38bd/fonts/NotoColorEmoji.ttf' d71fc7ac3febadb6256123e8fb7c474a38e997bd
fc-cache -f "$font_dir"
