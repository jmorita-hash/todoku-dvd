# 動画の読み取りと、DVD用（MPEG-2）への変換

# 長さ（秒・切り捨て）を返す。読めなければ空
media_duration() {
  "$FFMPEG" -hide_banner -i "$1" 2>&1 \
    | sed -n 's/.*Duration: \([0-9][0-9]*\):\([0-9][0-9]\):\([0-9][0-9]\).*/\1 \2 \3/p' \
    | head -1 | awk '{ print $1*3600 + $2*60 + $3 }'
}

# 音声トラックがあれば 1、なければ 0
media_has_audio() {
  if "$FFMPEG" -hide_banner -i "$1" 2>&1 | grep -q "Stream #.*: Audio:"; then echo 1; else echo 0; fi
}

# 前後の無地画面の秒数を確認して返す（空なら既定値）。不正ならエラー終了
media_pad_sec() {
  local p="${1:-$PAD_SEC}"
  # 全角数字・空白・「秒」を許す（例: "１０秒" → 10）
  p="$(echo "$p" | sed -e 's/０/0/g' -e 's/１/1/g' -e 's/２/2/g' -e 's/３/3/g' -e 's/４/4/g' \
       -e 's/５/5/g' -e 's/６/6/g' -e 's/７/7/g' -e 's/８/8/g' -e 's/９/9/g' -e 's/秒//g' -e 's/　//g' -e 's/[[:space:]]//g')"
  case "$p" in ''|*[!0-9]*) td_die "前後の無地画面の秒数は、0〜${PAD_SEC_MAX}の数字で入力してください。" 4;; esac
  p=$(( 10#$p ))
  [ "$p" -le "$PAD_SEC_MAX" ] || td_die "前後の無地画面の秒数は、0〜${PAD_SEC_MAX}の数字で入力してください。" 4
  echo "$p"
}

# 長さと前後の秒数から映像ビットレート(kbps)を決める。DVD 1枚に入らなければ空
media_video_kbps() {
  local total=$(( $1 + $2 * 2 ))
  local all=$(( DISC_BYTES / 1000 * 8 / total ))
  local v=$(( all * 95 / 100 - AUDIO_KBPS ))   # 5% は多重化の余裕
  [ "$v" -gt "$VIDEO_MAX_KBPS" ] && v=$VIDEO_MAX_KBPS
  if [ "$v" -lt "$VIDEO_MIN_KBPS" ]; then echo ""; else echo "$v"; fi
}

# 映像フィルタ：16:9の枠に収める → 29.97fps → 720x480(アナモルフィック) → 前後に無地画面
media_video_filter() {
  local pad="$1" w=854 sar="32/27"
  if [ "$ASPECT" = "4:3" ]; then w=640; sar="8/9"; fi
  local f="scale=${w}:480:force_original_aspect_ratio=decrease,pad=${w}:480:(ow-iw)/2:(oh-ih)/2:black,fps=30000/1001,scale=720:480,setsar=${sar},format=yuv420p"
  [ "$pad" -gt 0 ] && f="${f},tpad=start_duration=${pad}:stop_duration=${pad}:start_mode=add:stop_mode=add:color=${PAD_COLOR}"
  echo "$f"
}

# 変換を始める（バックグラウンド）
media_encode_start() {
  local work="$1" in="$2"
  local dur has_audio vk pad
  dur="$(td_meta_get "$work" duration)"
  has_audio="$(td_meta_get "$work" has_audio)"
  vk="$(td_meta_get "$work" video_kbps)"
  pad="$(td_meta_get "$work" pad_sec)"
  local total=$(( dur + pad * 2 ))
  local vf af fc
  vf="$(media_video_filter "$pad")"
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
    -target "${TV_STANDARD}-dvd" -aspect "$ASPECT" \
    -b:v "${vk}k" -maxrate 9000k -bufsize 1835k -b:a "${AUDIO_KBPS}k" \
    -t "$total" -progress "$work/progress.txt" -nostats "$work/movie.mpg"
  td_log "encode start: dur=${dur}s pad=${pad}s audio=${has_audio} video=${vk}k"
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
