# 実装履歴

- 2025-11-15
  - run_sub_converter.ps1 をUTF-8(BOM)で再作成。英語メッセージ化。
  - after_move で動画ファイルパスから同名ベースの字幕を検出する方式に変更。
  - 特殊文字対応のため `-LiteralPath` を徹底使用。
  - シンプルな `.srv3` を `.srt` に変換する関数 `ConvertTo-SimpleSrt` を追加。
  - `<span>`/`<u>` を検出した場合のみ YTSubConverter.exe で `.ass` に変換。
  - YTSubConverter.exe 自動探索 `Find-YTSubConverter` を実装（環境変数 `YTSC_PATH`/同ディレクトリ/PATH/動画フォルダ）。
  - 見つからない場合はASS変換をスキップし、処理継続するよう変更。
  - デバッグ出力の式展開バグを修正（`$var.*.srv3` → フォーマット演算子）。
  - win yt-dlp config を `--exec after_move` で PowerShell スクリプトを呼ぶよう更新。
  - run_sub_converter_wrapper.cmd 追加（必要に応じて利用可）。
