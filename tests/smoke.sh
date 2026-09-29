#!/bin/bash
# 動作テスト：テスト動画を作って、変換 → DVD組み立て →（macOSなら）ディスクイメージ作成まで通す
#
# 使い方:
#   tests/smoke.sh <todoku-dvd.sh のパス>
#   例）ビルド済みアプリ: tests/smoke.sh "dist/Todoku DVD.app/Contents/Resources/app/todoku-dvd.sh"
#       ソースのまま（ffmpeg / dvdauthor を環境変数で指定）:
#           FFMPEG=/usr/bin/ffmpeg DVDAUTHOR=/path/to/dvdauthor tests/smoke.sh app/todoku-dvd.sh
set -u
CLI="${1:?todoku-dvd.sh のパスを指定してください}"
T="$(mktemp -d)"
export HOME="$T/home"; mkdir -p "$HOME"
export TD_LOG="$T/test.log"
cat > "$T/test.conf" <<EOF
OUTPUT_DIR="$T/out"
UPDATE_REPO=""
EOF
export TD_CONFIG="$T/test.conf"
FAILS=0
pass() { echo "  OK  $*"; }
fail() { echo "  NG  $*"; FAILS=$((FAILS+1)); }

# テスト動画の作成には、アプリと同じ ffmpeg を使う
bash "$CLI" prepare >/dev/null || { echo "prepare failed"; cat "$TD_LOG"; exit 1; }
FF="${FFMPEG:-$(ls "$HOME/Library/Application Support/TodokuDVD"/bin-*/ffmpeg 2>/dev/null | head -1)}"
[ -x "$FF" ] || { echo "ffmpeg not found"; exit 1; }
echo "ffmpeg: $FF ($(uname -m))"
"$FF" -version | head -1

"$FF" -loglevel error -y -f lavfi -i testsrc2=s=1920x1080:r=30:d=12 -f lavfi -i sine=f=440:d=12 \
  -c:v mpeg4 -q:v 5 -c:a aac -shortest "$T/テスト_16x9.mp4" || exit 1
"$FF" -loglevel error -y -f lavfi -i testsrc=s=1440x1080:r=24:d=8 -c:v mpeg4 -q:v 5 "$T/noaudio_4x3.mov" || exit 1
echo "broken" > "$T/broken.mp4"

echo "[1] probe"
r="$(bash "$CLI" probe "$T/テスト_16x9.mp4")" && [ "$r" = "12|1|8000|10" ] && pass "16:9 音声あり・前後10秒(既定) → $r" || fail "16:9 probe → $r"
r="$(bash "$CLI" probe "$T/noaudio_4x3.mov" "３秒")" && [ "$r" = "8|0|8000|3" ] && pass "4:3 音声なし・前後3秒(全角入力) → $r" || fail "4:3 probe → $r"
bash "$CLI" probe "$T/noaudio_4x3.mov" 99 >/dev/null 2>&1; [ $? -eq 4 ] && pass "秒数が範囲外ならエラー" || fail "秒数の範囲チェック"
bash "$CLI" probe "$T/broken.mp4" >/dev/null 2>&1; [ $? -eq 2 ] && pass "壊れたファイルはエラー" || fail "壊れたファイル"

for f in "テスト_16x9.mp4:10:32" "noaudio_4x3.mov:3:14"; do
  name="${f%%:*}"; rest="${f#*:}"; pad="${rest%%:*}"; expect="${rest##*:}"
  echo "[2] $name"
  W="$(bash "$CLI" work-new)"
  bash "$CLI" encode-start "$W" "$T/$name" "$pad" >/dev/null || { fail "encode-start"; continue; }
  while :; do
    st="$(bash "$CLI" encode-status "$W")" || { fail "encode-status"; break; }
    case "$st" in done*) break;; esac
    sleep 1
  done
  [ "$st" = "done|100" ] && pass "変換" || continue
  bash "$CLI" author "$W" >/dev/null && pass "組み立て" || { fail "組み立て"; continue; }
  V="$W/DVD/VIDEO_TS/VTS_01_1.VOB"
  info="$("$FF" -hide_banner -i "$V" 2>&1)"
  echo "$info" | grep -q "mpeg2video.*720x480.*DAR 16:9" && pass "映像 MPEG-2 720x480 16:9" || fail "映像形式"
  echo "$info" | grep -q "ac3, 48000 Hz, stereo" && pass "音声 AC-3 48kHz" || fail "音声形式"
  d="$(echo "$info" | sed -n 's/.*Duration: 00:00:\([0-9][0-9]\).*/\1/p' | head -1)"
  [ "${d#0}" -ge $((expect-1)) ] 2>/dev/null && [ "${d#0}" -le $((expect+1)) ] && pass "長さ ${d}秒（前後${pad}秒込み）" || fail "長さ ${d}秒（期待 ${expect}秒）"
  yavg() { "$FF" -v error -ss "$1" -i "$V" -an -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - | sed -n 's/.*YAVG=\([0-9]*\).*/\1/p' | head -1; }
  y1="$(yavg 1)"; y2="$(yavg $((pad + 2)))"; y3="$(yavg $((expect - 1)))"
  [ -n "$y1" ] && [ "$y1" -le 17 ] && pass "先頭は無地(黒) Y=$y1" || fail "先頭が無地でない Y=$y1"
  [ -n "$y2" ] && [ "$y2" -gt 30 ] && pass "本編あり Y=$y2" || fail "本編が映っていない Y=$y2"
  [ -n "$y3" ] && [ "$y3" -le 17 ] && pass "末尾は無地(黒) Y=$y3" || fail "末尾が無地でない Y=$y3"
  rm="$(od -A n -t x1 -j 35 -N 1 "$W/DVD/VIDEO_TS/VIDEO_TS.IFO" | tr -d ' ')"
  [ "$rm" = "00" ] && pass "リージョンフリー（地域制限なし）" || fail "リージョン制限あり ($rm)"
  grep -q "<post>exit;</post>" "$W/dvd.xml" && pass "リピートなし（最後で停止）" || fail "リピート設定"
  if command -v hdiutil >/dev/null; then
    iso="$(bash "$CLI" make-iso "$W" "テスト")" && [ -f "$iso" ] && pass "ISO作成 $(du -h "$iso" | cut -f1)" || { fail "ISO作成"; continue; }
    mnt="$(hdiutil attach -readonly -nobrowse "$iso" | sed -n 's#.*\(/Volumes/.*\)#\1#p' | head -1)"
    [ -f "$mnt/VIDEO_TS/VIDEO_TS.IFO" ] && pass "ISOの中身 VIDEO_TS" || fail "ISOの中身 ($mnt)"
    hdiutil detach "$mnt" >/dev/null 2>&1
  else
    echo "  --  ISO作成（hdiutil がないので省略）"
  fi
  bash "$CLI" cleanup "$W" >/dev/null; [ ! -d "$W" ] && pass "後片付け" || fail "後片付け"
done

echo "[3] その他"
bash "$CLI" version
echo "disc-state: $(bash "$CLI" disc-state 2>/dev/null || echo '(なし)')"
bash "$CLI" check-update --force >/dev/null && pass "更新チェック（設定なし）" || fail "更新チェック"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED: $FAILS"; echo "--- log ---"; tail -50 "$TD_LOG"; fi
rm -rf "$T"
exit "$FAILS"
