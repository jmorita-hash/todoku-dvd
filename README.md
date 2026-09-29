# Todoku DVD

Final Cut Pro で書き出した結婚式ムービーを、**メニューなし・自動再生**の DVD にする Mac アプリ。
Intel・Apple製チップの両方で動く（macOS 12 以降）。

- 動画をアイコンにドラッグ＆ドロップ → 変換 → DVD-R に書き込み（何枚でも続けて焼ける）
- DVD-R／DVD-Video形式／NTSC・リージョンフリー／メニューなし／リピートなし／ファイナライズ済み
- 前後に無地画面・無音（既定 10 秒、作業時に1本ごとに変更可）
- 新しいバージョンが出たら起動時にお知らせ

サイトに載せている DVD の注釈との対応は [docs/SPEC.md](docs/SPEC.md)。

## 作業者への配布

最新版はいつもこの URL から落とせる（Releases の最新版）。

```
https://github.com/<所有者>/<リポジトリ>/releases/latest/download/TodokuDVD.zip
```

使い方は [docs/worker-guide.txt](docs/worker-guide.txt)（zip にも「はじめにお読みください.txt」として同梱）。

> Apple の正式署名はしていないため、初回だけ「システム設定 → プライバシーとセキュリティ → このまま開く」が必要。

## 新しいバージョンの出し方

1. 変更する
2. `app/VERSION` の数字を上げる（例: `0.2.0` → `0.3.0`）
3. `CHANGELOG.md` に変更内容を書く（`## 0.3.0` の見出しで）
4. main に push → GitHub Actions が Mac（Apple製チップ・Intel）でビルドとテスト
5. テストが通ったらタグを打って push

   ```
   git tag v0.3.0 && git push origin v0.3.0
   ```

6. Actions が Releases に `TodokuDVD.zip` を公開 → 作業者のアプリに更新のお知らせが出る

## 構成

```
app/
  ui/main.applescript   画面（ダイアログ・進捗バー・ドラッグ＆ドロップ）
  todoku-dvd.sh         処理の入口（小さなコマンドの集まり。画面から呼ばれる）
  lib/
    common.sh           設定読み込み・ログ・同梱ツールの準備・バックグラウンド処理
    media.sh            動画の読み取りと MPEG-2 への変換（ffmpeg）
    dvd.sh              DVD の形への組み立て（dvdauthor）
    disc.sh             ディスクイメージ作成・ドライブ確認・書き込み（hdiutil / drutil）
    update.sh           新バージョンの確認（GitHub Releases）
  config/defaults.conf  設定の既定値（前後の秒数、画質、保存先など）
  templates/dvd.xml     DVD の構成（メニュー・チャプターを足すならここ）
  VERSION               アプリのバージョン（ここだけ変えれば全体に反映）
build/                  Mac 上でのビルド（ffmpeg 取得、dvdauthor ビルド、アプリ組み立て）
tests/smoke.sh          動作テスト（テスト動画を作って変換〜ISO作成まで通す）
docs/                   作業者向け手順書、設計メモ
```

拡張のしかたは [docs/DESIGN.md](docs/DESIGN.md) を参照。

## 手元の Mac でビルドする場合

```
brew install bison flex
build/fetch-ffmpeg.sh
build/build-dvdauthor.sh
build/make-app.sh
tests/smoke.sh "dist/Todoku DVD.app/Contents/Resources/app/todoku-dvd.sh"
```

## 同梱ソフトウェア

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照（FFmpeg・dvdauthor は GPL）。
