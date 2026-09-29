#!/bin/bash
# ffmpeg（Intel用・Apple製チップ用）を取得して、1つのユニバーサルバイナリにまとめる（macOS上で実行）
# 出力: build/out/ffmpeg
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out cache

# 配布元とチェックサムは固定（勝手に中身が変わらないように）
BASE="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0"
X64_SHA="a12354fce7eb62361473bbe10d53a1893695babd35869ec8e92e5dfea8d0440b"
ARM_SHA="6be74d6f449889c2e87a75873894f8520cad56c08ac76f2a628d85b0519daaca"

fetch() {
  local name="$1" sha="$2"
  if [ ! -f "cache/$name" ]; then
    curl -fsSL --retry 3 -o "cache/$name" "$BASE/$name"
  fi
  echo "$sha  cache/$name" | shasum -a 256 -c -
  gunzip -c "cache/$name" > "cache/${name%.gz}"
}

fetch ffmpeg-darwin-x64.gz "$X64_SHA"
fetch ffmpeg-darwin-arm64.gz "$ARM_SHA"
lipo -create -output out/ffmpeg cache/ffmpeg-darwin-x64 cache/ffmpeg-darwin-arm64
chmod 755 out/ffmpeg
lipo -info out/ffmpeg
