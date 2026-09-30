#!/bin/bash
# GitHub Actions 用：コマンドを実行し、失敗したら出力の最後の部分を
# エラー注釈（annotation）として残す。ログ全体を開かなくても原因が分かるようにするため。
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
if [ "$rc" -ne 0 ]; then
  msg="$(tail -40 "$log" | sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}')"
  echo "::error title=$(basename "$1") failed (exit $rc)::${msg}"
fi
rm -f "$log"
exit "$rc"
