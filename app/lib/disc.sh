# ディスクイメージ作成・ドライブの状態確認・書き込み（macOS標準の hdiutil / drutil）

disc_make_iso() {
  local work="$1" name="$2"
  mkdir -p "$OUTPUT_DIR" || td_die "保存先フォルダを作れませんでした：$OUTPUT_DIR"
  disc_cleanup_old
  local iso="$OUTPUT_DIR/${name}_$(date '+%Y%m%d-%H%M%S').iso"
  hdiutil makehybrid -iso -udf -udf-version 1.02 \
      -iso-volume-name "$VOLUME_NAME" -udf-volume-name "$VOLUME_NAME" \
      -o "$iso" "$work/DVD" >> "$LOG" 2>&1 \
    || td_die "ディスクイメージの作成に失敗しました。"
  [ -f "$iso" ] || td_die "ディスクイメージが見つかりません。"
  td_log "iso: $iso"
  echo "$iso"
}

disc_cleanup_old() {
  [ "${KEEP_ISO_DAYS:-0}" -gt 0 ] 2>/dev/null || return 0
  find "$OUTPUT_DIR" -maxdepth 1 -name '*.iso' -type f -mtime +"$KEEP_ISO_DAYS" -print -delete >> "$LOG" 2>&1
}

# none=ディスクなし / blank=空 / used=書き込み済み / nodrive=ドライブなし / unknown
disc_state() {
  local s
  s="$(drutil status 2>&1)"
  echo "$s" >> "$LOG"
  if echo "$s" | grep -qi "No Media"; then echo none
  elif echo "$s" | grep -qi "Writability:.*blank"; then echo blank
  elif echo "$s" | grep -qi "Type:"; then echo used
  elif [ -z "$(echo "$s" | tr -d '[:space:]')" ] || echo "$s" | grep -qi "no drive\|not found"; then echo nodrive
  else echo unknown
  fi
}

disc_burn_start() {
  local work="$1" iso="$2"
  [ -f "$iso" ] || td_die "ディスクイメージが見つかりません。"
  local verify="-verifyburn"
  [ "$VERIFY_BURN" = "1" ] || verify="-noverifyburn"
  rm -f "$work/burn.txt"
  td_log "burn start: $iso"
  td_job_start "$work" burn /bin/sh -c 'exec hdiutil burn -puppetstrings "$1" "$2" > "$0" 2>&1' "$work/burn.txt" "$verify" "$iso"
}

# 進捗(0-100)。分からないときは -1
disc_burn_percent() {
  local p
  p="$(grep -o 'PERCENT:[-0-9.]*' "$1/burn.txt" 2>/dev/null | tail -1 | cut -d: -f2 | cut -d. -f1)"
  case "$p" in ''|-*) echo -1;; *) echo "$p";; esac
}
