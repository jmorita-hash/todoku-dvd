# 共通：パス・設定の読み込み・ログ・同梱ツールの準備
# macOS標準の bash 3.2 で動く書き方にしている（連想配列などは使わない）

TD_VERSION="$(cat "$TD_ROOT/VERSION" 2>/dev/null || echo "0.0.0-dev")"
TD_SUPPORT_DIR="$HOME/Library/Application Support/TodokuDVD"
LOG="${TD_LOG:-$HOME/Library/Logs/TodokuDVD.log}"

mkdir -p "$(dirname "$LOG")" "$TD_SUPPORT_DIR" 2>/dev/null

# 設定：既定値 → 作業者ごとの上書き の順に読む
. "$TD_ROOT/config/defaults.conf"
[ -f "$TD_SUPPORT_DIR/config.conf" ] && . "$TD_SUPPORT_DIR/config.conf"
[ -n "$TD_CONFIG" ] && [ -f "$TD_CONFIG" ] && . "$TD_CONFIG"   # テスト用

td_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# 失敗時：画面に出す日本語メッセージを標準エラーに出して終了
td_die() {
  td_log "ERROR: $1"
  echo "$1" >&2
  exit "${2:-1}"
}

# 同梱ツール（ffmpeg / dvdauthor）の場所を決める。
# アプリ内のものを「Application Support」にコピーし、ダウンロード品の印
# （quarantine）を外してから使う。アプリがどこに置かれても確実に動かすため。
td_prepare_tools() {
  if [ -n "$FFMPEG" ] && [ -n "$DVDAUTHOR" ]; then return 0; fi   # テスト時は環境変数で指定
  local src="$TD_ROOT/../bin"
  local dst="$TD_SUPPORT_DIR/bin-$TD_VERSION"
  if [ ! -x "$dst/ffmpeg" ] || [ ! -x "$dst/dvdauthor" ]; then
    [ -f "$src/ffmpeg" ] && [ -f "$src/dvdauthor" ] \
      || td_die "アプリの部品が見つかりません。アプリを入れ直してください。"
    rm -rf "$TD_SUPPORT_DIR"/bin-* 2>/dev/null
    mkdir -p "$dst" || td_die "作業用フォルダを作れませんでした。"
    cp "$src/ffmpeg" "$src/dvdauthor" "$dst/" || td_die "アプリの部品をコピーできませんでした。"
    chmod 755 "$dst/ffmpeg" "$dst/dvdauthor"
    xattr -dr com.apple.quarantine "$dst" 2>/dev/null
    td_log "tools installed: $dst"
  fi
  FFMPEG="$dst/ffmpeg"
  DVDAUTHOR="$dst/dvdauthor"
}

# 作業フォルダの中の値を読み書きする小さな仕組み（key=value）
td_meta_set() { echo "$2=$3" >> "$1/meta"; }
td_meta_get() { grep "^$2=" "$1/meta" 2>/dev/null | tail -1 | cut -d= -f2-; }

# バックグラウンドで動かしているジョブ（変換・書き込み）の共通処理
# 引数: 作業フォルダ ジョブ名 コマンド...
td_job_start() {
  local work="$1" name="$2"; shift 2
  rm -f "$work/$name.exit" "$work/$name.pid"
  (
    "$@" &
    echo $! > "$work/$name.pid"
    wait $!
    echo $? > "$work/$name.exit"
  ) </dev/null >/dev/null 2>&1 &
  # pid ファイルができるまで少し待つ
  local i=0
  while [ ! -f "$work/$name.pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
}

# running / done / failed のどれかを返す
td_job_state() {
  local work="$1" name="$2"
  if [ -f "$work/$name.exit" ]; then
    if [ "$(cat "$work/$name.exit")" = "0" ]; then echo "done"; else echo "failed"; fi
  elif [ -f "$work/$name.pid" ] && kill -0 "$(cat "$work/$name.pid")" 2>/dev/null; then
    echo running
  elif [ -f "$work/$name.pid" ]; then
    sleep 1   # 終了直後で exit ファイルがまだ書かれていない場合
    if [ -f "$work/$name.exit" ] && [ "$(cat "$work/$name.exit")" = "0" ]; then echo "done"; else echo "failed"; fi
  else
    echo failed
  fi
}

td_job_kill() {
  local pid
  pid="$(cat "$1/$2.pid" 2>/dev/null)"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
}
