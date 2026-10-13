# Verification profile

This directory contains public synthetic fixtures, provenance, the explicit Godot
host limitation, and checksum pins for the reviewed Linux x86-64 engines.

ユーザーのメッセージ、private log、credential、製品用 payload は含みません。

## Engines and process contract

The floor is official Godot 4.3 stable; current stable at review (2026-10-05) is
Godot 4.7.2.

`script/install_godot.py` は、固定した公式 SHA512 checksum manifest、archive の SHA512 と SHA256、正確な member 一覧、展開した engine の SHA256 を検証します。tool は source tree の外へインストールします。

native program は `--headless --no-header --path ... --script ... --` で実行します。Godot 4.3 の `--quiet` は、engine header とともにアプリケーションの JSON stdout も抑止し、その版には `Engine.print_to_stdout` setter がありません。header やエラーの filtering は行いません。すべての response は厳密な JSON で、各 request に対し正確に 1 response を要求します。終了状態、stderr、末尾出力、timeout、source 一覧、入出力 digest、最後の process 終了を検査します。通常の検証は stderr が空であることを要求します。意図的に子 process を失敗させるテストは、その失敗を記録して拒否し、製品の成功数には含めません。

各 runtime は、source の外に分離された書込み可能な HOME と XDG directory を持ちます。Godot が作る `.godot` cache directory と `.gd.uid` sidecar は source 一覧から除外します。これらは engine が生成する metadata であり、配布する library source ではありません。実際の GDScript と fixture の bytes は引き続き source に結び付けます。native library module は別の言語や process を呼び出しません。Python、Perl/TypeScript/Nim の oracle 生成 utility、SVG rasterizer、ZXing は開発専用です。

## Complete checked corpus

- Public: 5,610 request（生成 3,028 件、見積り 1,920 件、容量 640 件、Structured Append set 22 件）。独立に生成した Nayuki の version/ECC/mask matrix 1,280 件を含みます
- Internal: 4,576 request（raw-codeword matrix 4,320 件、RS degree 255 件、65,536 積を網羅する GF(256) 結果 1 件）
- 共有 regression corpus: 正確に 102 件の percent/FNC1 vector。独立に導出した成功 70 件、forced-alpha error 10 件、容量エラー 22 件に加え、手動指定の意味、Digital Link、現行 TypeScript authority 互換性、不正 authority、print-DPI、ECC 境界を検査
- GS1: 変更していない過去 request 全 1,411 件を、新たに実行した現行 TypeScript の結果と照合。一致 1,243 件と明示的な residual 168 件（診断 132 件、受理から拒否へ 34 件、安全な dot-query 2 件）。復元した全 80 case を別途検査し、診断順序の移行 5 件には独立した Nim witness を使用
- Native: core、GS1、描画、Structured Append、不正な native Variant、所有権、循環、UTF-8 scalar の妥当性、NUL bytes、integer と boolean の型、diagnostics の独立性、順序を入れ替えた Structured Append merge
- 実際の subprocess 失敗 control: 終了間際の stderr、非ゼロ終了、余分な stdout、duplicate/nonfinite JSON、timeout、出力欠落、source 改変、不正な decoder レコード、不正な PNG framing を成功にはしません。独立した GS1 の受理検証も、一律エラーによる誤成功の control と予期しないフィールドを拒否します

固定した public FNC1 overlay は、現行 TypeScript の修正 8 件だけに適用し、元の各 request と期待結果を結び付けます。別の 8 case の Godot NUL host overlay は、正確な public fixture index 2624–2631 に結び付き、変更された文字列が一致したと扱わず、型付き `INVALID_INPUT` 拒否を記録します。Godot 4.3 は文字列中の U+0000 を除去し、Godot 4.7.2 は U+FFFD へ置換します。binary の Array/PackedByteArray 入力はゼロを含む全 byte を保持し、テスト対象です。fixture は省略しません。最小版の fgets-based test adapter には ASCII JSON escape を渡すため、1,023 byte の入力 chunk が UTF-8 scalar を分断することはありません。現行 Godot は native の raw stdin byte API を使います。この adapter はテスト protocol であり、ライブラリの公開 text-input API ではありません。

## Independent output checks

renderer の既定 scale は 8 です。ZXing-C++ 3.1.1 は、暗黙の既定値と明示的な scale の同一性を含め、その scale で実際に出力した PNG を復号します。ZXing Java 3.5.4 の厳密な detector suite は scale 3 の実 PNG を使い、matrix fallback、PURE_BARCODE による迂回、失敗の容認は行いません。Structured Append header、payload bytes、parity、ECI、GS1 identifier は別々に検査します。

A separate ten-case Java scale-8 characterization pins exactly one known
`NotFoundException` pair (`alphanumeric-L-0`) and nine successful pairs. Each
candidate is compared to an independently rendered identical-pixel PNG. All ten
have positive matrix, scale-3 PNG and C++ controls. The rejected pair is reported
as rejected and is never counted as successful PNG detection.

SVG bytes/data URL と raster 出力は、独立した rasterizer と decoder で別途検証します。再利用可能な receipt は、実際の source・engine・decoder の bytes、コマンドライン、正確な件数、process の終了、stderr、入出力 hash に結び付けます。

変更していない共有 GS1 入力は、独立に記録した現行 TypeScript の全 49 操作で実行します。native overlay は、安全な dot builder 2 件と不正 host の診断 1 件の、正確に 3 件です。有効な IPv4 alias 6 件から、authority の受理検査 18 件を作ります。残る不正な example.0x 入力は、拒否検査 3 件すべてを維持します。完全な source pin と正確な residual 分類は `gs1/README.md` を参照してください。
