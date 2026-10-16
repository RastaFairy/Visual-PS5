# Visual-PS5 — PS5 Homebrew Studio 1.1.0

Windows 向けローカルビジュアル IDE です。UI 設計、プロジェクト管理、コード確認、C++20 UI 生成、PS5 コミュニティツールチェーンを利用したビルドを行います。

**言語の状態：** アプリの UI は現在スペイン語です。日本語マニュアルは利用できますが、UI 翻訳は別作業として実施します。

## ドキュメント

- [日本語ユーザーマニュアル](docs/USER-MANUAL.ja-JP.md)
- [スペイン語マニュアル](docs/MANUAL.es-ES.md)
- [英語マニュアル](docs/USER-MANUAL.en-GB.md)
- [フランス語マニュアル](docs/USER-MANUAL.fr-FR.md)
- [ドイツ語マニュアル](docs/USER-MANUAL.de-DE.md)
- [簡体字中国語マニュアル](docs/USER-MANUAL.zh-CN.md)
- [ロシア語マニュアル](docs/USER-MANUAL.ru-RU.md)
- [クレジットと upstream 帰属](docs/CREDITS.md)
- [SDK / upstream プロジェクト一覧](release/UPSTREAM-SDK-MATRIX.md)
- [変更履歴](docs/CHANGELOG.md)

## クイックスタート

1. 対象の開発ブランチのパッケージをダウンロードまたは作成します。
2. Windows 10/11 の書き込み可能なフォルダーに展開します。
3. start.bat を実行し、ブラウザーが開かなければ http://127.0.0.1:47813/ にアクセスします。

PowerShell 7 を推奨しますが、Windows PowerShell 5.1 もサポートします。ネイティブビルドには Git、WSL/Linux、選択したテンプレートの依存関係が必要です。サービスは 127.0.0.1 のみで待ち受けます。

メンテナーは .ffpfsc イメージが実機で正常に動作したと報告していますが、すべてのタイトルやファームウェアの動作を保証するものではありません。本プロジェクトは Sony 公式 SDK ではなく、独自ファイル、ファームウェア、キー、ゲーム、BIOS は含みません。