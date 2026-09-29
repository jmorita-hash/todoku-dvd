#!/bin/bash
# Todoku DVD の処理部分（コマンド）。画面側（ui/main.applescript）から呼ばれる。
# 1コマンド = 1つの小さな仕事。結果は標準出力に1行、失敗時は日本語の
# メッセージを標準エラーに出して 0 以外で終わる。
#
# 使い方: todoku-dvd.sh <コマンド> [引数...]
#   version                 バージョンを表示
#   prepare                 同梱ツールの準備（起動時に1回）
#   probe <動画>            「長さ秒|音声あり(1/0)|映像kbps」
#   work-new                作業フォルダを作ってパスを表示
#   encode-start <作業> <動画>
#   encode-status <作業>    「running|進捗」「done|100」
#   author <作業>           DVDの形に組み立てる
#   make-iso <作業> <名前>  ディスクイメージを作ってパスを表示
#   disc-state              none / blank / used / nodrive / unknown
#   burn-start <作業> <iso>
#   burn-status <作業>      「running|進捗(-1=不明)」「done|100」
#   cancel <作業>           実行中の変換・書き込みを止める
#   cleanup <作業>          作業フォルダを消す
#   check-update [--force]  「新バージョン|URL」または none
#   log-path                ログファイルの場所
#   run <動画> [名前]       変換〜ディスクイメージ作成までを一気に（テスト用）

TD_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$TD_ROOT/lib/common.sh"
. "$TD_ROOT/lib/media.sh"
. "$TD_ROOT/lib/dvd.sh"
. "$TD_ROOT/lib/disc.sh"
. "$TD_ROOT/lib/update.sh"

need_work() { [ -n "$1" ] && [ -d "$1" ] || td_die "作業フォルダが見つかりません。"; }

cmd="$1"; shift
case "$cmd" in
  version)
    echo "$TD_VERSION"
    ;;

  prepare)
    td_log "===== v$TD_VERSION $(uname -m) macOS $(sw_vers -productVersion 2>/dev/null)"
    td_prepare_tools
    echo ok
    ;;

  probe)
    td_prepare_tools
    [ -f "$1" ] || td_die "動画ファイルが見つかりません。"
    dur="$(media_duration "$1")"
    [ -n "$dur" ] && [ "$dur" -gt 0 ] || td_die "この動画ファイルは読み込めませんでした。
Final Cut Proで書き出し直してから、もう一度お試しください。" 2
    vk="$(media_video_kbps "$dur")"
    [ -n "$vk" ] || td_die "動画が長すぎてDVD 1枚に入りません（目安：約1時間半まで）。" 3
    echo "$dur|$(media_has_audio "$1")|$vk"
    ;;

  work-new)
    mktemp -d "${TMPDIR:-/tmp}/todokudvd.XXXXXX" || td_die "作業用フォルダを作れませんでした。"
    ;;

  encode-start)
    need_work "$1"; td_prepare_tools
    info="$("$0" probe "$2")" || exit $?
    IFS='|' read -r dur has_audio vk <<EOF
$info
EOF
    td_meta_set "$1" duration "$dur"
    td_meta_set "$1" has_audio "$has_audio"
    td_meta_set "$1" video_kbps "$vk"
    td_log "input: $2"
    media_encode_start "$1" "$2"
    echo started
    ;;

  encode-status)
    need_work "$1"
    case "$(td_job_state "$1" encode)" in
      running) echo "running|$(media_encode_percent "$1")";;
      done)    [ -s "$1/movie.mpg" ] && echo "done|100" || td_die "変換に失敗しました。";;
      *)       td_die "変換に失敗しました。";;
    esac
    ;;

  author)
    need_work "$1"; td_prepare_tools
    dvd_author "$1"
    echo ok
    ;;

  make-iso)
    need_work "$1"
    name="$(echo "${2:-movie}" | tr '/:' '__')"
    disc_make_iso "$1" "$name"
    ;;

  disc-state)
    disc_state
    ;;

  burn-start)
    need_work "$1"
    disc_burn_start "$1" "$2"
    echo started
    ;;

  burn-status)
    need_work "$1"
    case "$(td_job_state "$1" burn)" in
      running) echo "running|$(disc_burn_percent "$1")";;
      done)    td_log "burn ok"; echo "done|100";;
      *)       cat "$1/burn.txt" >> "$LOG" 2>/dev/null
               td_die "書き込みに失敗しました。
ディスクを取り出し、新しい空のDVD-Rでやり直してください。";;
    esac
    ;;

  cancel)
    [ -n "$1" ] && [ -d "$1" ] || exit 0
    td_job_kill "$1" encode
    td_job_kill "$1" burn
    td_log "cancelled"
    echo ok
    ;;

  cleanup)
    # 念のため、work-new で作ったフォルダ以外は消さない
    [ -d "$1" ] && case "$(basename "$1")" in todokudvd.*) rm -rf "$1";; esac
    echo ok
    ;;

  check-update)
    update_check "$1"
    ;;

  log-path)
    echo "$LOG"
    ;;

  run)
    [ -f "$1" ] || td_die "動画ファイルが見つかりません。"
    work="$("$0" work-new)" || exit 1
    "$0" encode-start "$work" "$1" >/dev/null || exit 1
    while :; do
      st="$("$0" encode-status "$work")" || exit 1
      case "$st" in done*) break;; esac
      sleep 1
    done
    "$0" author "$work" >/dev/null || exit 1
    name="${2:-$(basename "${1%.*}")}"
    "$0" make-iso "$work" "$name" || exit 1
    "$0" cleanup "$work" >/dev/null
    ;;

  *)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 64
    ;;
esac
