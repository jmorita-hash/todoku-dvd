# 新しいバージョンの確認（GitHub の最新 Release と比べる）

# a > b なら 0 を返す（x.y.z 形式）
update_is_newer() {
  local a="${1#v}" b="${2#v}"
  a="${a%%-*}"; b="${b%%-*}"
  local IFS=.
  set -- $a 0 0 0
  local a1=$1 a2=$2 a3=$3
  set -- $b 0 0 0
  local b1=$1 b2=$2 b3=$3
  [ "$a1" -gt "$b1" ] 2>/dev/null && return 0; [ "$a1" -lt "$b1" ] 2>/dev/null && return 1
  [ "$a2" -gt "$b2" ] 2>/dev/null && return 0; [ "$a2" -lt "$b2" ] 2>/dev/null && return 1
  [ "$a3" -gt "$b3" ] 2>/dev/null && return 0
  return 1
}

# 新しい版があれば「バージョン|ダウンロードページURL」、なければ none
update_check() {
  [ -n "$UPDATE_REPO" ] || { echo none; return; }
  local stamp="$TD_SUPPORT_DIR/last-update-check"
  if [ "$1" != "--force" ] && [ -f "$stamp" ]; then
    local age=$(( $(date +%s) - $(cat "$stamp" 2>/dev/null || echo 0) ))
    [ "$age" -lt $(( UPDATE_CHECK_HOURS * 3600 )) ] && { echo none; return; }
  fi
  date +%s > "$stamp" 2>/dev/null
  local json tag
  json="$(curl -fsSL --max-time 5 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$UPDATE_REPO/releases/latest" 2>/dev/null)" || { echo none; return; }
  tag="$(echo "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -n "$tag" ] && update_is_newer "$tag" "$TD_VERSION"; then
    td_log "update available: $tag"
    echo "${tag#v}|https://github.com/$UPDATE_REPO/releases/latest"
  else
    echo none
  fi
}
