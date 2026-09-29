#!/bin/bash
# dvdauthor をソースから Intel・Apple製チップ両対応（ユニバーサル）でビルドする（macOS上で実行）
# 必要なもの: Xcode コマンドラインツール、Homebrew の bison と flex
# 出力: build/out/dvdauthor
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out cache

REPO="https://github.com/ldo/dvdauthor.git"
COMMIT="fe8fe3578f95f34889e7ed17591d02dceb4f42ed"   # 固定（2021-11-05）
SRC="cache/dvdauthor"

if [ ! -d "$SRC/.git" ]; then
  git clone -q "$REPO" "$SRC"
fi
git -C "$SRC" checkout -q "$COMMIT"

# 構文解析器の生成（macOS付属の bison は古いので Homebrew 版を使う）
BISON="$(brew --prefix bison)/bin/bison"
FLEX="$(brew --prefix flex)/bin/flex"
( cd "$SRC/src" \
  && "$FLEX" -s -B -Cem -odvdvml.c -Pdvdvm dvdvml.l \
  && "$BISON" -o dvdvmy.c -d -p dvdvm dvdvmy.y )

cp dvdauthor-config.h "$SRC/config.h"
SDK="$(xcrun --show-sdk-path)"

clang -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 -O2 -w \
  -DHAVE_CONFIG_H -DSYSCONFDIR='"/etc"' \
  -I"$SRC" -I"$SRC/src" -I"$SDK/usr/include/libxml2" \
  "$SRC"/src/{dvdauthor,dvdcompile,dvdvml,dvdvmy,dvdifo,dvdvob,dvdpgc,dvdcli,readxml,conffile,compat}.c \
  -lxml2 -o out/dvdauthor

chmod 755 out/dvdauthor
lipo -info out/dvdauthor
otool -L out/dvdauthor
