# 2分にしてね

## Mitene Video Converter

> 動画を放り込むと、みてねに上げられる形になる。

「2分にしてね」は、家族アルバム「みてね」にアップロードする動画を、Mac上で自動的に分割・軽量化するmacOSアプリです。

動画の形式や解像度を確認して、変換設定を選ぶ必要はありません。動画をドロップすると、みてね用のMP4として別ファイルに書き出します。元の動画は変更しません。

## できること

- MP4・MOV・M4Vをドラッグ＆ドロップで受け付ける
- 複数の動画をキューに入れ、1本ずつ順番に処理する
- H.264のMP4へ変換し、解像度とフレームレートをみてね向けに整える
- 119秒を超える動画を、極端に短い最後のファイルができないよう均等に分割する
- 元動画の撮影日時を引き継ぎ、分割した動画には開始位置を加算する
- 変換後の動画をFinderで表示する、または写真アプリへ追加する

変換は外部サーバーへ動画を送らず、Mac上だけで行います。

## 使い方

1. アプリを起動します。
2. 動画をウインドウへドロップするか、「または動画を選ぶ」を押します。
3. 変換が終わったら、Finderで確認するか、写真アプリへ追加します。
4. 写真アプリに追加した動画を、iPhoneのみてねアプリからアップロードします。

出力先は `~/Movies/2分にしてね/` です。ファイル名には `_mitene` が付き、分割時は `_mitene_01` のような連番になります。同名ファイルがあっても上書きしません。

## 開発環境

- macOS 14 Sonoma以降
- Swift 6
- XcodeまたはSwift toolchain

このリポジトリはSwift Packageとして構成しています。

```sh
swift test
swift run MiteneVideoConverter
```

実動画を使う統合テストでは、テスト用動画を作るためにローカルの `ffmpeg` を利用します。アプリ本体はFFmpegに依存していません。`ffmpeg` がない環境では、そのテストはスキップされます。

## 出力の基本ルール

| 項目 | ルール |
| --- | --- |
| コンテナ | MP4 |
| 映像 | H.264 / AVC |
| 色 | SDR / BT.709 |
| 解像度 | 横は最大1280×720、縦は最大720×1280。アスペクト比を維持し、アップスケールしない |
| フレームレート | 最大30fps |
| 長さ | 1本119秒以下 |

詳しい入出力契約や画面の方針は [SPEC.md](SPEC.md) にまとめています。

## プロジェクト構成

```text
Sources/MiteneVideoConverter/
├── ContentView.swift              # SwiftUIの画面
├── AppModel.swift                 # 入力キューと処理状態
├── VideoModels.swift              # 解析結果と変換計画
├── VideoConverter.swift            # AVFoundationによる変換
└── PhotoLibraryExporter.swift      # 写真アプリへの追加

Tests/MiteneVideoConverterTests/
├── ConversionPlannerTests.swift    # 分割・解像度・日時の計画
└── VideoPipelineIntegrationTests.swift

docs/
├── index.html                      # GitHub Pages用LP
└── styles.css
```

## 開発状況

> [!NOTE]
> このリポジトリには、Swift Packageから起動できる開発版アプリと、GitHub Pages用のLPが含まれます。署名済みアプリ、DMG、Releaseページからのダウンロードはまだ用意していません。

「2分にしてね - Mitene Video Converter」は、みてねを利用しやすくする非公式ツールです。みてねへの直接ログインや直接アップロードは行いません。
