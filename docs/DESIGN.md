# 設計メモ（拡張のしかた）

## 考え方

**画面**と**処理**を分けている。

- 画面 … `app/ui/main.applescript`。ダイアログ・進捗バー・ドラッグ＆ドロップだけを受け持つ。
- 処理 … `app/todoku-dvd.sh` のコマンド群。画面はこれを `do shell script` で呼ぶだけ。

処理コマンドは「1コマンド = 1つの小さな仕事」「成功なら結果を1行出力」「失敗なら日本語メッセージを
標準エラーに出して終了コード≠0」という約束で統一している。画面側はエラー文をそのまま表示する。
この約束を守れば、処理の中身（ffmpeg の設定など）を変えても画面は触らなくてよいし、
将来画面を別の技術（SwiftUI など）に作り替えても処理はそのまま使える。

処理はすべてターミナルからも動かせるので、画面なしで試せる。

```
app/todoku-dvd.sh run ~/Movies/test.mov          # 変換〜ISO作成まで一気に
app/todoku-dvd.sh probe ~/Movies/test.mov        # 12|1|8000
```

時間のかかる処理（変換・書き込み）は `*-start` でバックグラウンド開始、`*-status` で進捗を聞く形。
共通の仕組みは `common.sh` の `td_job_start / td_job_state / td_job_kill`。

## よくある拡張と、触る場所

| やりたいこと | 触る場所 |
|---|---|
| 画質、保存先を変える | `app/config/defaults.conf` |
| 作業者ごとに設定を変える | 作業者の Mac の `~/Library/Application Support/TodokuDVD/config.conf` に同じ書式で書く |
| 前後の無地画面の既定秒数・色を変える | `PAD_SEC` / `PAD_COLOR`（1本ごとの変更は作業時の入力欄で） |
| 再生後にループさせる | `END_ACTION="loop"`（※サイトでは「リピートなし」と表記しているので、変えるならサイトも直す） |
| チャプターやメニューを付ける | `app/templates/dvd.xml`（dvdauthor の XML）と `lib/dvd.sh` |
| 変換の中身（フィルタ・音量調整など）を変える | `lib/media.sh` の `media_video_filter` / `media_encode_start` |
| 新しい工程を足す（例: 盤面ラベル印刷） | `lib/` に新しいファイル → `todoku-dvd.sh` にコマンド追加 → `main.applescript` の `processMovie` に1行追加 |
| 画面の文言を変える | `app/ui/main.applescript` |
| ブルーレイ対応など大きな拡張 | `lib/` に別モジュールを作り、`templates/` に別の構成を置く |

新しい処理を足したら `tests/smoke.sh` にも確認を1つ足すこと（GitHub Actions が Intel・Apple製チップの両方で実行する）。

## 同梱ツールの扱い

- `ffmpeg` … ffmpeg-static b6.0 の Intel 版と Apple製チップ版を `lipo` で1つにまとめる（チェックサム固定）
- `dvdauthor` … ソース（コミット固定）から clang でユニバーサルビルド。macOS 標準の libxml2 を使う
- 起動時に `~/Library/Application Support/TodokuDVD/bin-<バージョン>/` へコピーし、ダウンロード品の印
  （quarantine）を外してから使う。アプリがどこに置かれていても動かすため。

## まだ Mac 実機で確認できていないこと

- 実際の DVD-R への書き込み（`drutil status` の判定、`hdiutil burn -puppetstrings` の進捗）
  → GitHub のテスト環境には DVD ドライブがないため。作業者の Mac で試し焼きして確認する
- 焼いた DVD が家庭用プレーヤーで自動再生されるか
