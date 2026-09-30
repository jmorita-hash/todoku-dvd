-- Todoku DVD の画面部分
-- ・ダブルクリック → 動画ファイルを選ぶ画面
-- ・動画をアイコンにドラッグ＆ドロップ → そのまま開始
-- できるDVD: DVD-R / DVD-Video形式 / NTSC・リージョンフリー / メニューなし / 前後に無地画面（既定10秒）/
--            リピートなし（最後まで再生したら停止）/ ファイナライズ済み
-- 実際の処理はすべて Contents/Resources/app/todoku-dvd.sh（コマンド）に任せる。
-- 画面の文言や流れを変えるときはこのファイル、処理を変えるときは app/lib/*.sh を直す。

property appName : "Todoku DVD"

on run
	try
		set movieFile to choose file with prompt "DVDにする動画ファイル（Final Cut Proで書き出したもの）を選んでください" of type {"public.movie"}
	on error number -128
		return
	end try
	processMovie(POSIX path of movieFile)
end run

on open droppedItems
	if (count of droppedItems) > 1 then
		showInfo("動画は1本ずつにしてください。" & return & "最初の1本だけ処理します。")
	end if
	processMovie(POSIX path of (item 1 of droppedItems))
end open

-- ===== 全体の流れ =====
on processMovie(inPath)
	set work to ""
	try
		cli("prepare", {})
		checkUpdate()

		-- 1) 内容の確認と、前後の無地画面の秒数（通常10秒。お客様の指定があれば変更）
		set probeInfo to splitText(cli("probe", {inPath}), "|")
		set padSec to item 4 of probeInfo
		set movieName to baseName(inPath)
		repeat
			set dur to (item 1 of probeInfo) as integer
			set msg to "次の動画をDVDにします。" & return & return & ¬
				"・ファイル：" & movieName & return & ¬
				"・長さ：" & (dur div 60) & "分" & (dur mod 60) & "秒" & return & return & ¬
				"前後に入れる無地画面の秒数を下の欄に入力してください。" & return & ¬
				"（通常は10秒。お客様の指定があればその秒数に）"
			if item 2 of probeInfo is "0" then set msg to msg & return & return & "※この動画には音声がありません。無音のDVDになります。"
			activate
			set dlgResult to display dialog msg default answer padSec with title appName buttons {"やめる", "はじめる"} default button 2 with icon note
			if button returned of dlgResult is not "はじめる" then return
			set padSec to text returned of dlgResult
			try
				set probeInfo to splitText(cli("probe", {inPath, padSec}), "|")
				set padSec to item 4 of probeInfo
				exit repeat
			on error errMsg number errNum
				if errNum is -128 then error number -128
				showInfo(errMsg)
			end try
		end repeat

		-- 2) 変換
		set work to cli("work-new", {})
		setProgress("手順 1/3：DVD用に変換しています", "このままお待ちください（途中でやめる場合は「停止」）", 0)
		cli("encode-start", {work, inPath, padSec})
		waitJob("encode-status", work)

		-- 3) 組み立て・ディスクイメージ作成
		setProgress("手順 2/3：DVDの形に組み立てています", "もう少しお待ちください", -1)
		cli("author", {work})
		set isoPath to cli("make-iso", {work, movieName})

		-- 4) 焼く（何枚でも）
		set burned to burnLoop(work, isoPath)
		resetProgress()
		if burned > 0 then
			showInfo("完了しました（" & burned & "枚）。" & return & return & ¬
				"焼いたDVDは、発送前に必ずDVDプレーヤーで最初から最後まで再生して確認してください。" & return & return & ¬
				"ディスクイメージは「ムービー」フォルダの「Todoku DVD」に保存しています（焼き直しに使えます）。")
		else
			showInfo("DVDには焼かずに終了しました。" & return & return & ¬
				"ディスクイメージは「ムービー」フォルダの「Todoku DVD」に保存しています。")
		end if
	on error errMsg number errNum
		resetProgress()
		if work is not "" then
			try
				cli("cancel", {work})
			end try
		end if
		if errNum is not -128 then showError(errMsg)
	end try
	if work is not "" then
		try
			cli("cleanup", {work})
		end try
	end if
end processMovie

on burnLoop(work, isoPath)
	set burned to 0
	repeat
		resetProgress()
		if burned is 0 then
			set msg to "準備ができました。" & return & return & "空のDVD-Rをドライブに入れて「DVDに焼く」を押してください。"
		else
			set msg to (burned as text) & "枚焼き上がりました。" & return & return & "もう1枚焼く場合は、新しい空のDVD-Rを入れて「DVDに焼く」を押してください。"
		end if
		if askUser(msg, {"終わる", "DVDに焼く"}) is not "DVDに焼く" then exit repeat

		set jobState to cli("disc-state", {})
		if jobState is "none" then
			showInfo("ディスクが入っていません。空のDVD-Rを入れてください。")
		else if jobState is "used" then
			showInfo("このディスクはすでに書き込み済みです。新しい空のDVD-Rを入れてください。")
		else if jobState starts with "wrongtype" then
			showInfo("このディスクは「" & (item 2 of splitText(jobState, "|")) & "」です。" & return & "DVD-R（マイナスR）を使ってください。")
		else if jobState is "nodrive" then
			showInfo("DVDドライブが見つかりません。ドライブがMacにつながっているか確認してください。")
		else
			setProgress("手順 3/3：DVDに書き込んでいます", "終わるとディスクが自動で出てきます。ドライブに触らないでください", 0)
			try
				cli("burn-start", {work, isoPath})
				waitJob("burn-status", work)
				set burned to burned + 1
			on error errMsg number errNum
				if errNum is -128 then error number -128
				resetProgress()
				showError(errMsg)
			end try
		end if
	end repeat
	return burned
end burnLoop

-- 変換・書き込みが終わるまで進捗を表示しながら待つ
on waitJob(statusCmd, work)
	repeat
		set jobState to splitText(cli(statusCmd, {work}), "|")
		if item 1 of jobState is "done" then exit repeat
		set pct to (item 2 of jobState) as integer
		if pct < 0 then
			set progress total steps to -1
		else
			set progress total steps to 100
			set progress completed steps to pct
		end if
		delay 1
	end repeat
	set progress completed steps to 100
end waitJob

on checkUpdate()
	try
		set dlgResult to cli("check-update", {})
		if dlgResult is not "none" then
			set parts to splitText(dlgResult, "|")
			if askUser("新しいバージョン（" & item 1 of parts & "）があります。" & return & return & ¬
				"ダウンロードページを開いて最新版を入れてください。今回はこのまま続けることもできます。", ¬
				{"このまま続ける", "ダウンロードページを開く"}) is "ダウンロードページを開く" then
				open location (item 2 of parts)
			end if
		end if
	end try
end checkUpdate

-- ===== 部品 =====

-- 処理コマンドを呼ぶ。失敗時はコマンドが出した日本語メッセージでエラーになる
on cli(cmd, args)
	set tool to (POSIX path of (path to me)) & "Contents/Resources/app/todoku-dvd.sh"
	set cmdLine to "/bin/bash " & quoted form of tool & " " & cmd
	repeat with oneArg in args
		set cmdLine to cmdLine & " " & quoted form of (oneArg as text)
	end repeat
	return do shell script cmdLine
end cli

on setProgress(desc, subDesc, startPct)
	if startPct < 0 then
		set progress total steps to -1
	else
		set progress total steps to 100
		set progress completed steps to startPct
	end if
	set progress description to desc
	set progress additional description to subDesc
end setProgress

on resetProgress()
	set progress total steps to 0
	set progress completed steps to 0
	set progress description to ""
	set progress additional description to ""
end resetProgress

on askUser(msg, btns)
	activate
	return button returned of (display dialog msg with title appName buttons btns default button (count of btns) with icon note)
end ask

on showInfo(msg)
	activate
	display dialog msg with title appName buttons {"OK"} default button 1 with icon note
end showInfo

on showError(msg)
	set logPath to ""
	try
		set logPath to cli("log-path", {})
	end try
	activate
	display dialog msg & return & return & "うまくいかない場合は、次のファイルを管理者に送ってください。" & return & logPath ¬
		with title appName buttons {"OK"} default button 1 with icon stop
end showError

on splitText(srcText, delim)
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delim
	set parts to text items of srcText
	set AppleScript's text item delimiters to oldTID
	return parts
end splitText

on baseName(pathText)
	set parts to splitText(pathText, "/")
	set fileName to item -1 of parts
	if fileName is "" then set fileName to item -2 of parts
	set dotParts to splitText(fileName, ".")
	if (count of dotParts) > 1 then
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "."
		set fileName to (items 1 thru -2 of dotParts) as text
		set AppleScript's text item delimiters to oldTID
	end if
	return fileName
end baseName
