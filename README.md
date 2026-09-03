# 2分にしてね

## Mitene Video Converter

みてねへのアップロード用に動画を分割・軽量化するmacOSアプリです。

> 動画を放り込むと、みてねに上げられる形になる。

動画はMacの中だけで処理します。入力動画は変更せず、`~/Movies/2分にしてね/` に別ファイルとして保存します。

## 開発

Xcode 26.6以降またはSwift 6以降で、Swift Packageとして開発できます。

```sh
swift test
swift run MiteneVideoConverter
```

## 仕様

詳しい要件は [SPEC.md](SPEC.md) を参照してください。

## 注意

「2分にしてね - Mitene Video Converter」は、家族アルバム「みてね」を利用しやすくする非公式ツールです。みてねへの直接投稿は行わず、変換した動画を写真アプリへ追加してから、いつものみてねアプリでアップロードします。
