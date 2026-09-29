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

# 長さから映像ビットレート(kbps)を決める。DVD 1枚に入らなければ空
media_video_kbps() {
  local total=$(( $1 + PAD_SEC * 2 ))
  local all=$(( DISC_BYTES / 1000 * 8 / total ))
  local v=$(( all * 95 / 100 - AUDIO_KBPS ))   # 5% は多重化の余裕
  [ "$v" -gt "$VIDEO_MAX_KBPS" ] && v=$VIDEO_MAX_KBPS
  if [ "$v" -lt "$VIDEO_MIN_KBPS" ]; then echo ""; else echo "$v"; fi
}

# 映像フィルタ：16:9の枠に収める → 29.97fps → 720x480(アナモルフィック) → 前後に黒
media_video_filter() {
  local w=854 sar="32/27"
  if [ "$ASPECT" = "4:3" ]; then w=640; sar="8/9"; fi
  echo "scale=${w}:480:force_original_aspect_ratio=decrease,pad=${w}:480:(ow-iw)/2:(oh-ih)/2:black,fps=30000/1001,scale=720:480,setsar=${sar},format=yuv420p,tpad=start_duration=${PAD_SEC}:stop_duration=${PAD_SEC}:start_mode=add:stop_mode=add:color=black"
}

# 変換を始める（バックグラウンド）
media_encode_start() {
  local work="$1" in="$2"
  local dur has_audio vk
  dur="$(td_meta_get "$work" duration)"
  has_audio="$(td_meta_get "$work" has_audio)"
  vk="$(td_meta_get "$work" video_kbps)"
  local total=$(( dur + PAD_SEC * 2 ))
  local vf af fc
  vf="$(media_video_filter)"
  af="aresample=48000,aformat=channel_layouts=stereo,adelay=$(( PAD_SEC * 1000 )):all=1,apad"
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
  td_log "encode start: dur=${dur}s audio=${has_audio} video=${vk}k"
  rm -f "$work/progress.txt" "$work/movie.mpg"
  td_job_start "$work" encode /bin/sh -c 'exec "$@" >> "$0" 2>&1' "$LOG" "$@"
}

# 進捗(0-100)
media_encode_percent() {
  local work="$1" dur us
  dur="$(td_meta_get "$work" duration)"
  us="$(grep '^out_time_us=' "$work/progress.txt" 2>/dev/null | tail -1 | cut -d= -f2)"
  case "$us" in ''|*[!0-9]*) echo 0; return;; esac
  local p=$(( us / 10000 / (dur + PAD_SEC * 2) ))
  [ "$p" -gt 99 ] && p=99
  echo "$p"
}
