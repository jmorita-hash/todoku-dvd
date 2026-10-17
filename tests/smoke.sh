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
"$FF" -loglevel error -y -f lavfi -i testsrc2=s=1280x720:r=30:d=6.5 -f lavfi -i sine=f=440:d=6.5 \
  -c:v mpeg4 -q:v 5 -c:a aac -shortest "$T/hasuu.mp4" || exit 1
echo "broken" > "$T/broken.mp4"

echo "[1] probe"
r="$(bash "$CLI" probe "$T/テスト_16x9.mp4")" && [ "$r" = "12|1|8000|5|16:9|black|12.00" ] && pass "16:9 音声あり・既定（黒・5秒・16:9） → $r" || fail "16:9 probe → $r"
r="$(bash "$CLI" probe "$T/noaudio_4x3.mov" "３秒" "４：３" "白")" && [ "$r" = "8|0|8000|3|4:3|white|8.00" ] && pass "音声なし・全角入力（3秒・4:3・白） → $r" || fail "全角入力 probe → $r"
r="$(bash "$CLI" probe "$T/hasuu.mp4" 0 "" "#f5e6d3")" && case "$r" in 7\|1\|8000\|0\|16:9\|#F5E6D3\|6.5*) true;; *) false;; esac \
  && pass "長さの端数は切り上げ・色番号 → $r" || fail "端数・色番号 probe → $r"
bash "$CLI" probe "$T/noaudio_4x3.mov" 99 >/dev/null 2>&1; [ $? -eq 4 ] && pass "秒数が範囲外ならエラー" || fail "秒数の範囲チェック"
bash "$CLI" probe "$T/noaudio_4x3.mov" 99999999999999999999 >/dev/null 2>&1; [ $? -eq 4 ] && pass "桁の多すぎる秒数はエラー" || fail "桁の多すぎる秒数"
bash "$CLI" probe "$T/noaudio_4x3.mov" 5 "21:9" >/dev/null 2>&1; [ $? -eq 5 ] && pass "縦横比が16:9・4:3以外ならエラー" || fail "縦横比のチェック"
bash "$CLI" probe "$T/noaudio_4x3.mov" 5 "" "#12345" >/dev/null 2>&1; [ $? -eq 6 ] && pass "色番号の形が違えばエラー" || fail "色のチェック"
bash "$CLI" probe "$T/broken.mp4" >/dev/null 2>&1; [ $? -eq 2 ] && pass "壊れたファイルはエラー" || fail "壊れたファイル"

# ファイル名;前後秒;縦横比;色;出来上がりの長さ(秒・小数)
for f in "テスト_16x9.mp4;;;;22.00" "noaudio_4x3.mov;3;4:3;white;14.00" "hasuu.mp4;0;16:9;black;6.50"; do
  IFS=';' read -r name pad aspect color expect_exact <<EOF
$f
EOF
  [ -n "$pad" ] || pad=5
  [ -n "$aspect" ] || aspect="16:9"
  [ -n "$color" ] || color=black
  expect="$(echo "$expect_exact" | cut -d. -f1)"
  echo "[2] $name（前後${pad}秒・${aspect}・${color}）"
  W="$(bash "$CLI" work-new)"
  # 空の引数は既定値（黒・5秒・16:9）が使われることも確かめる
  case "$name" in テスト_*) set -- ;; *) set -- "$pad" "$aspect" "$color";; esac
  bash "$CLI" encode-start "$W" "$T/$name" "$@" >/dev/null || { fail "encode-start"; continue; }
  while :; do
    st="$(bash "$CLI" encode-status "$W")" || { fail "encode-status"; break; }
    case "$st" in done*) break;; esac
    sleep 1
  done
  [ "$st" = "done|100" ] && pass "変換" || continue
  # 出来上がりの長さが本編（小数まで）＋前後の秒数と合っているか（本編の最後が欠けていないか）
  got="$("$FF" -hide_banner -i "$W/movie.mpg" 2>&1 | sed -n 's/.*Duration: 00:\([0-9][0-9]\):\([0-9][0-9]\.[0-9][0-9]\).*/\1 \2/p' | head -1 | awk '{ printf "%.2f", $1*60 + $2 }')"
  awk -v g="$got" -v e="$expect_exact" 'BEGIN { exit !(g >= e - 0.1 && g <= e + 0.2) }' \
    && pass "長さ ${got}秒（期待 ${expect_exact}秒・本編が欠けていない）" || fail "長さ ${got}秒（期待 ${expect_exact}秒）"
  bash "$CLI" author "$W" >/dev/null && pass "組み立て" || { fail "組み立て"; continue; }
  V="$W/DVD/VIDEO_TS/VTS_01_1.VOB"
  info="$("$FF" -hide_banner -i "$V" 2>&1)"
  echo "$info" | grep -q "mpeg2video.*720x480.*DAR ${aspect}" && pass "映像 MPEG-2 720x480 ${aspect}" || fail "映像形式（期待 ${aspect}）"
  echo "$info" | grep -q "ac3, 48000 Hz, stereo" && pass "音声 AC-3 48kHz" || fail "音声形式"
  d="$(echo "$info" | sed -n 's/.*Duration: 00:00:\([0-9][0-9]\).*/\1/p' | head -1)"
  [ "${d#0}" -ge $((expect-1)) ] 2>/dev/null && [ "${d#0}" -le $((expect+1)) ] && pass "DVDの長さ ${d}秒（前後${pad}秒込み）" || fail "DVDの長さ ${d}秒（期待 ${expect}秒）"
  yavg() { "$FF" -v error -ss "$1" -i "$V" -an -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - | sed -n 's/.*YAVG=\([0-9]*\).*/\1/p' | head -1; }
  is_pad() {   # 無地画面の明るさが、指定した色どおりか
    case "$color" in
      white) [ -n "$1" ] && [ "$1" -ge 200 ];;
      *)     [ -n "$1" ] && [ "$1" -le 17 ];;
    esac
  }
  y2="$(yavg $((pad + 2)))"
  [ -n "$y2" ] && [ "$y2" -gt 30 ] && [ "$y2" -lt 200 ] && pass "本編あり Y=$y2" || fail "本編が映っていない Y=$y2"
  if [ "$pad" -gt 0 ]; then
    y1="$(yavg 1)"; y3="$(yavg $((expect - 1)))"
    is_pad "$y1" && pass "先頭は無地(${color}) Y=$y1" || fail "先頭が無地(${color})でない Y=$y1"
    is_pad "$y3" && pass "末尾は無地(${color}) Y=$y3" || fail "末尾が無地(${color})でない Y=$y3"
  fi
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
