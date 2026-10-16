# ユーザーマニュアル — PS5 Homebrew Studio 1.1.5

最終更新：2026年10月16日。アプリの UI は現在スペイン語です。マニュアルの翻訳は UI 自体のローカライズ完了を意味しません。

## 1. 必要環境

起動には Windows 10/11 とアプリフォルダーへの読み書き権限が必要です。PowerShell 7 を推奨しますが、Windows PowerShell 5.1 もサポートします。

ビルドには Git、WSL/Linux、選択したバックエンドの upstream 依存関係が必要です。SharpProspero/C# は使用中の upstream リビジョンが指定する .NET が必要です。ネイティブ C++ テンプレートには互換性のあるツールチェーンが必要です。UltraPack には Python 3.10 以降と [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack) が必要です。

## 2. インストールと起動

1. テストする開発ブランチのパッケージをダウンロードまたは作成します。
2. Windows の保護された場所を避け、書き込み可能なフォルダーに展開します。
3. start.bat を実行し、PowerShell のサーバーウィンドウを開いたままにします。
4. ブラウザーが自動で開かなければ http://127.0.0.1:47813/ にアクセスします。
5. サービスを停止するにはサーバーウィンドウを閉じるか STOP.bat を使います。

サービスは 127.0.0.1 のみで待ち受けます。ネットワークへ公開したり、0.0.0.0 に変更したりしないでください。プロジェクトは通常 Documents/PS5HomebrewStudio/Projects に保存されます。

## 3. UI とビジュアルプロジェクト

1920×1080 のキャンバスは仮想作業領域であり、PS5 システム UI の正確な画像ではありません。コンポーネントパネルで要素を追加し、インスペクターで位置やプロパティを変更し、階層と画面管理で UI を整理します。フローエディターは、対応するコンポーネントとバックエンドに対して notify、setText、toggleVisibility、setValue、changeColor、navigate などの操作をイベントに接続します。

プロジェクトを作成したら依存関係を準備する前にバックエンドを選びます。コンポーネントとリソースを追加し、ID の重複を避け、画面を設定します。診断を実行し、無効な参照を修正します。Ctrl+S で保存します。モデルや ZIP のエクスポートはネイティブビルドではありません。

## 4. バックエンドとビルド

**SharpProspero / C#：** upstream の実際のパイプラインと .NET/NativeAOT を使用します。導入したコミットが要求する .NET バージョンを確認してください。

**ネイティブ OpenGL / C++20：** ps5-homebrew-ui の契約に対応した画面を生成します。画像は RGBA8 に変換され、最大 512×512 ピクセル、画面ごとの固有テクスチャ ID は 16 個までです。

**Vulkan/RADV / C++20：** PS5_VulkanTemplate でタイトルを作成し、互換性のある Vulkan UI モジュールへ統合します。PS5_Vulkan、PS5_Mesa/RADV、PS5_PayloadSDK、PS5_VKHomebrewUI の互換リビジョンが必要です。

IDE は実際の upstream スクリプトを実行し、ログを保存します。終了コード 0 だけでは不十分で、ネイティブタイトルには eboot.bin と sce_sys/param.json が必要です。Sony 独自 SDK は含まれず、すべてのファームウェアでの動作は保証されません。

## 5. ネイティブアプリの表示リソース

**プロジェクト**で `sce_sys/param.json` を持つ初期化済みタイトルを開き、**Presentación** を選択します。未選択の項目は変更されません。

- **アイコン：** `sce_sys/icon0.png`（512×512 PNG）。

- **選択時の背景：** `sce_sys/pic0.dds`。**起動/ロード時の背景：** `sce_sys/pic1.dds`。それぞれ 3840×2160 の DDS BC7/DX10 に変換され、別々の画像を使えます。まだ両方ない場合は初回に2枚とも選択してください。DirectXTex の `texconv` が必要です（`winget install Microsoft.DirectXTex.Texconv`）。

- **アプリ選択時の音楽：** `sce_sys/snd0.at9`（48 kHz、ループする ATRAC9、最大2 MiB）。互換性のある AT9 は直接指定できます。MP3/WAV/OGG/M4A の変換には FFmpeg と、適法に入手した互換 ATRAC9 エンコーダーが必要です。IDE はエンコーダーを配布・ダウンロードしません。

上流の `tools/prepare-assets.ps1` が適用前に形式を検証します。これらは個別アプリの表示リソースであり、PS5 全体の壁紙や起動音は変更しません。システムテーマは別プロジェクトの [ps5-theme](https://github.com/Blaze414/ps5-theme) を参照してください。

## 6. UltraPack でのパッケージ作成

1. 「ツール」で Python 3.10 以降と UltraPack の backend/cli.py を設定します。
2. 設定を保存します。パスはローカルの .runtime/integrations.json に記録されます。
3. ビルド済みのネイティブプロジェクトを選び、「パッケージ」を実行します。
4. .ffpfs、.ffpfsc、.pkg を選びます。Windows で .pkg を作るにはネイティブ helper と依存関係が必要です。
5. 「ソースと内容を検証」をオンにして --verify を渡します。検証には時間とメモリが追加で必要になる場合があります。
6. 最終ログ、終了コード、出力パス、警告を確認します。以前の実行で残ったファイルを今回の成功と見なさないでください。

出力は packages-ultrapack 内に形式とタイムスタンプごとに保存されます。処理はバックグラウンドで動くため、エディターは応答を続けます。メンテナーによれば、生成された .ffpfsc イメージは実機で正常に動作しました。これは特定のテスト結果であり、すべてのタイトルやファームウェアを保証しません。

## 7. テストとトラブルシューティング

Node.js をインストールし、アプリフォルダーで node --check app.js、node --check runtime/native-generator.js、node runtime/test-native-generator.js を実行します。JavaScript の構文とジェネレーターケースを確認しますが、PS5 ツールチェーン全体のビルドや実機テストの代わりにはなりません。

サーバーが起動しない場合はエラー全文を保存し、PowerShell と権限を確認します。ビルドに失敗した場合はバックエンド、upstream のバージョン/コミット、全ログと終了コードを記録します。UltraPack では Python/cli.py、eboot.bin、sce_sys/param.json、出力先の権限を確認します。秘密情報を共有しないでください。


### WSL エラー：.git/config.lock の chmod に失敗する

ログに `chmod on /mnt/d/.../.git/config.lock failed: Operation not permitted` または `could not set 'core.filemode' to 'false'` が出る場合、WSL が `metadata` オプションなしで Windows ドライブをマウントしています。IDE は SDK のビルド前にこの状態を検出し、修正手順を表示します。

WSL ディストリビューションを開き、IDE に同梱されたスクリプトを実行してください（実際のインストール先に合わせてパスを変更します）。

```bash
sudo bash /mnt/d/PS5-Homebrew-Studio/runtime/fix-wsl-permissions.sh
```

スクリプトは `/etc/wsl.conf` のバックアップを作成し、ほかの設定を残したまま `[automount] options` を更新します。WSL を終了し、Windows PowerShell で `wsl --shutdown` を実行してからディストリビューションを再起動し、再ビルドしてください。このコマンドは実行中のすべての WSL ディストリビューションを停止するため、先に作業を保存します。Git や IDE を管理者として実行しないでください。[WSL 権限ガイド](WSL_PERMISSIONS.md) と [Microsoft の資料](https://learn.microsoft.com/windows/wsl/file-permissions)も参照してください。
## 8. ライセンスと制限

SDK、ドライバー、テンプレート、UI キットには個別のライセンスがあります。公開前に LICENSE、COPYING、NOTICE と再配布条件を確認してください。Visual-PS5 は Sony 公式 SDK ではなく、ファームウェア、キー、ゲーム、BIOS を含まず、タイトルを自動インストールしません。プレビューは PS5 エミュレーターではなく、実行時、音声、入力、永続化を検証しません。
