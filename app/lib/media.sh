# 動画の読み取りと、DVD用（MPEG-2）への変換

# 長さ（秒、小数2けた。例 12.70）を返す。読めなければ空
media_duration_exact() {
  "$FFMPEG" -hide_banner -i "$1" 2>&1 \
    | sed -n 's/.*Duration: \([0-9][0-9]*\):\([0-9][0-9]\):\([0-9][0-9]\)\.\([0-9][0-9]\).*/\1 \2 \3 \4/p' \
    | head -1 | awk '{ printf "%d.%02d\n", $1*3600 + $2*60 + $3, $4 }'
}

# 長さ（秒・切り上げ）。画質の計算と進捗に使う
media_duration_ceil() {
  echo "$1" | awk -F. '{ s = $1 + 0; if (($2 + 0) > 0) s++; print s }'
}

# 音声トラックがあれば 1、なければ 0
media_has_audio() {
  if "$FFMPEG" -hide_banner -i "$1" 2>&1 | grep -q "Stream #.*: Audio:"; then echo 1; else echo 0; fi
}

# 全角の数字・記号を半角に、空白を取り除く
media_normalize() {
  echo "$1" | sed -e 's/０/0/g' -e 's/１/1/g' -e 's/２/2/g' -e 's/３/3/g' -e 's/４/4/g' \
    -e 's/５/5/g' -e 's/６/6/g' -e 's/７/7/g' -e 's/８/8/g' -e 's/９/9/g' \
    -e 's/：/:/g' -e 's/＃/#/g' -e 's/　//g' -e 's/[[:space:]]//g'
}

# 前後の無地画面の秒数を確認して返す（空なら既定値）。不正ならエラー終了
media_pad_sec() {
  local p
  p="$(media_normalize "${1:-$PAD_SEC}" | sed -e 's/秒//g')"
  case "$p" in ''|*[!0-9]*) td_die "前後の無地画面の秒数は、0〜${PAD_SEC_MAX}の数字で入力してください。" 4;; esac
  [ "${#p}" -le 3 ] || td_die "前後の無地画面の秒数は、0〜${PAD_SEC_MAX}の数字で入力してください。" 4
  p=$(( 10#$p ))
  [ "$p" -le "$PAD_SEC_MAX" ] || td_die "前後の無地画面の秒数は、0〜${PAD_SEC_MAX}の数字で入力してください。" 4
  echo "$p"
}

# 画面の縦横比（16:9 / 4:3）を確認して返す（空なら既定値）
media_aspect() {
  local a
  a="$(media_normalize "${1:-$ASPECT}")"
  case "$a" in
    16:9|4:3) echo "$a";;
    *) td_die "画面の縦横比は「16:9」か「4:3」を選んでください。" 5;;
  esac
}

# 無地画面の色（black / white / #RRGGBB）を確認して返す（空なら既定値）
media_pad_color() {
  local c
  c="$(media_normalize "${1:-$PAD_COLOR}")"
  case "$c" in 黒) c=black;; 白) c=white;; esac
  case "$c" in
    black|white) echo "$c"; return 0;;
  esac
  if echo "$c" | grep -Eq '^#[0-9A-Fa-f]{6}$'; then
    echo "$c" | tr a-f A-F
  else
    td_die "無地画面の色は「黒」「白」か、#の後に英数字6けたの色番号（例：#F5E6D3）で指定してください。" 6
  fi
}

# 長さと前後の秒数から映像ビットレート(kbps)を決める。DVD 1枚に入らなければ空
media_video_kbps() {
  local total=$(( $1 + $2 * 2 ))
  local all=$(( DISC_BYTES / 1000 * 8 / total ))
  local v=$(( all * 95 / 100 - AUDIO_KBPS ))   # 5% は多重化の余裕
  [ "$v" -gt "$VIDEO_MAX_KBPS" ] && v=$VIDEO_MAX_KBPS
  if [ "$v" -lt "$VIDEO_MIN_KBPS" ]; then echo ""; else echo "$v"; fi
}

# 映像フィルタ：選んだ縦横比の枠に収める → 29.97fps → 720x480 → 前後に無地画面
# 引数: 前後秒 縦横比 色
media_video_filter() {
  local pad="$1" aspect="$2" color="$3" w=854 sar="32/27"
  if [ "$aspect" = "4:3" ]; then w=640; sar="8/9"; fi
  local f="scale=${w}:480:force_original_aspect_ratio=decrease,pad=${w}:480:(ow-iw)/2:(oh-ih)/2:black,fps=30000/1001,scale=720:480,setsar=${sar},format=yuv420p"
  [ "$pad" -gt 0 ] && f="${f},tpad=start_duration=${pad}:stop_duration=${pad}:start_mode=add:stop_mode=add:color=${color}"
  echo "$f"
}

# 変換を始める（バックグラウンド）
media_encode_start() {
  local work="$1" in="$2"
  local exact has_audio vk pad aspect color
  exact="$(td_meta_get "$work" duration_exact)"
  has_audio="$(td_meta_get "$work" has_audio)"
  vk="$(td_meta_get "$work" video_kbps)"
  pad="$(td_meta_get "$work" pad_sec)"
  aspect="$(td_meta_get "$work" aspect)"
  color="$(td_meta_get "$work" pad_color)"
  # 出来上がりの長さ＝本編（小数まで）＋前後の無地画面。切り捨てると本編や後ろの無地画面が欠けるため
  local total
  total="$(awk -v d="$exact" -v p="$pad" 'BEGIN { printf "%.2f", d + p * 2 }')"
  local vf af fc
  vf="$(media_video_filter "$pad" "$aspect" "$color")"
  af="aresample=48000,aformat=channel_layouts=stereo"
  [ "$pad" -gt 0 ] && af="${af},adelay=$(( pad * 1000 )):all=1"
  af="${af},apad"
  set -- "$FFMPEG" -hide_banner -nostdin -y -i "$in"
  if [ "$has_audio" = "1" ]; then
    fc="[0:v]${vf}[v];[0:a]${af}[a]"
  else
    set -- "$@" -f lavfi -i "anullsrc=r=48000:cl=stereo"
    fc="[0:v]${vf}[v];[1:a]anull[a]"
  fi
  set -- "$@" -filter_complex "$fc" -map "[v]" -map "[a]" \
    -target "${TV_STANDARD}-dvd" -aspect "$aspect" \
    -b:v "${vk}k" -maxrate 9000k -bufsize 1835k -b:a "${AUDIO_KBPS}k" \
    -t "$total" -progress "$work/progress.txt" -nostats "$work/movie.mpg"
  td_log "encode start: dur=${exact}s pad=${pad}s aspect=${aspect} color=${color} audio=${has_audio} video=${vk}k"
  rm -f "$work/progress.txt" "$work/movie.mpg"
  td_job_start "$work" encode /bin/sh -c 'exec "$@" >> "$0" 2>&1' "$LOG" "$@"
}

# 進捗(0-99)
media_encode_percent() {
  local work="$1" dur pad us
  dur="$(td_meta_get "$work" duration)"
  pad="$(td_meta_get "$work" pad_sec)"
  us="$(grep '^out_time_us=' "$work/progress.txt" 2>/dev/null | tail -1 | cut -d= -f2)"
  case "$us" in ''|*[!0-9]*) echo 0; return;; esac
  local p=$(( us / 10000 / (dur + pad * 2) ))
  [ "$p" -gt 99 ] && p=99
  echo "$p"
}
