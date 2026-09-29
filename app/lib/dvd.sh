# DVDビデオの形（VIDEO_TS）への組み立て

dvd_render_template() {
  # 再生が終わったら停止（exit）。loop の場合だけ最初に戻る
  local post="<post>exit;</post>"
  [ "$END_ACTION" = "loop" ] && post="<post>jump title 1;</post>"
  sed -e "s|{{TV_STANDARD}}|$TV_STANDARD|g" \
      -e "s|{{ASPECT}}|$ASPECT|g" \
      -e "s|{{AUDIO_LANG}}|$AUDIO_LANG|g" \
      -e "s|{{POST}}|$post|g" \
      "$TD_ROOT/templates/dvd.xml"
}

dvd_author() {
  local work="$1"
  [ -s "$work/movie.mpg" ] || td_die "変換済みの動画が見つかりません。"
  rm -rf "$work/DVD"
  dvd_render_template > "$work/dvd.xml"
  ( cd "$work" && VIDEO_FORMAT="$(echo "$TV_STANDARD" | tr a-z A-Z)" "$DVDAUTHOR" -x dvd.xml ) >> "$LOG" 2>&1 \
    || td_die "DVDの組み立てに失敗しました。"
  mkdir -p "$work/DVD/AUDIO_TS"
  [ -f "$work/DVD/VIDEO_TS/VIDEO_TS.IFO" ] && [ -f "$work/DVD/VIDEO_TS/VTS_01_0.IFO" ] \
    || td_die "DVDの組み立てに失敗しました（必要なファイルができていません）。"
  rm -f "$work/movie.mpg"
  td_log "authored: $work/DVD"
}
