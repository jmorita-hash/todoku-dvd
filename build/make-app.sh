#!/bin/bash
# 「Todoku DVD.app」を組み立てて、配布用の zip を作る（macOS上で実行）
# 先に build/fetch-ffmpeg.sh と build/build-dvdauthor.sh を実行しておくこと
# 出力: dist/Todoku DVD.app と dist/TodokuDVD.zip
#
# 環境変数 UPDATE_REPO=所有者/リポジトリ名 を渡すと、アプリの更新チェック先になる
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat app/VERSION)"
DIST="$ROOT/dist"
APP="$DIST/Todoku DVD.app"
PLIST="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy

rm -rf "$DIST"; mkdir -p "$DIST"

# 1) 画面部分（AppleScript）をアプリとしてコンパイル
osacompile -o "$APP" app/ui/main.applescript

# 2) 処理部分と同梱ツールを入れる
mkdir -p "$APP/Contents/Resources/app" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/licenses"
cp -R app/todoku-dvd.sh app/VERSION app/lib app/config app/templates "$APP/Contents/Resources/app/"
chmod 755 "$APP/Contents/Resources/app/todoku-dvd.sh"
if [ -n "${UPDATE_REPO:-}" ]; then
  sed -i '' "s|^UPDATE_REPO=\"\"|UPDATE_REPO=\"$UPDATE_REPO\"|" "$APP/Contents/Resources/app/config/defaults.conf"
fi
cp build/out/ffmpeg build/out/dvdauthor "$APP/Contents/Resources/bin/"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/licenses/"
cp build/cache/dvdauthor/COPYING "$APP/Contents/Resources/licenses/dvdauthor-COPYING.txt"

# 3) アプリ情報（キーがあれば書き換え、なければ追加）
plist_set() {
  $PB -c "Set :$1 $3" "$PLIST" 2>/dev/null || $PB -c "Add :$1 $2 $3" "$PLIST"
}
plist_set CFBundleIdentifier string jp.todoku-movie.dvd
plist_set CFBundleName string "Todoku DVD"
plist_set CFBundleDisplayName string "Todoku DVD"
plist_set CFBundleShortVersionString string "$VERSION"
plist_set CFBundleVersion string "$VERSION"
plist_set LSMinimumSystemVersion string 12.0
plist_set CFBundleDevelopmentRegion string ja
$PB -c Print "$PLIST"

# 4) 署名（Appleの正式署名ではなく、動かすための最低限の「自己署名」）
codesign --force --sign - "$APP/Contents/Resources/bin/ffmpeg" "$APP/Contents/Resources/bin/dvdauthor"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --verbose=2 "$APP"

# 5) 配布用 zip（アプリ＋作業者向け手順書）
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp docs/worker-guide.txt "$STAGE/はじめにお読みください.txt"
ditto -c -k --sequesterRsrc "$STAGE" "$DIST/TodokuDVD.zip"
rm -rf "$STAGE"
ls -lh "$DIST/TodokuDVD.zip"
echo "built Todoku DVD $VERSION"
