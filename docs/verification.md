# Verification and release scope

## Runtime versus development tools

runtime に必要なのは標準 Godot engine だけで、最小版は 4.3 です。検証 lane は公式 Linux x86-64 の 4.3 と現行 stable の 4.7.2 を使います。版は [公式 archive](https://godotengine.org/download/archive/) と [Linux download page](https://godotengine.org/download/linux/) に照合しました。`script/install_godot.py` は、実行前に公式の SHA512 release sum と固定した SHA256 binary/archive digest を検証します。ダウンロードした QR encoder はライブラリに含めません。

Python、開発専用の ZXing-C++ wheel、ZXing Java、librsvg は独立したテストツールです。任意の Perl/Nim/TypeScript oracle generator も開発専用です。`addons/specqr` を使うアプリケーションには、いずれも不要です。

The initial public scope includes the encoding core, scratch SVG/PNG, exact RGBA pixels and native Godot Image. Local graphical display setup encountered a sandbox Unix-socket permission denial. Consequently no GPU readback is claimed or counted as a pass, and the optional Texture convenience adapter is not part of this initial public API. Native PNG decoding and Image byte equality remain required. Windows, macOS, mobile and Web export were not executed.

## Immutable and fail-closed gates

`SOURCE-SHA256.json` は、それ自体と engine/Python が生成する metadata を除くすべての公開 source file の名前と hash を記録します。検証では新しいコピーを用意し、前後で正確なファイル一覧を確認して、レポートを source bytes、実際の interpreter hash、subprocess transcript に結び付けます。source の変更は gate を無効にします。すべての protocol process に、正確な response 数、正常終了、stderr が空であることを要求します。余分な行、parse warning、終了間際の失敗、残った response は受け入れません。

harness は、余分な出力、最後の非ゼロ終了、stderr、不正 JSON、欠落・過大 response、timeout を起こす敵対的な fake process を含みます。JSON 境界は厳密で上限を設けた RFC8259 実装です。重複キー、不正な Unicode/UTF-8、非有限数、資源超過は、Godot の許容的な JSON 動作へ委譲せず拒否します。

検証範囲はすべて維持します。

- 5,610 public + 4,576 internal = **10,186** 件の source に結び付いた参照 request
- 正確な全 **1,280** 通りの version/ECC/mask の組合せと、**4,320** 件の raw construction case
- GF(256) table、Reed–Solomon degree、容量と optimizer の case、control segment、SA metadata/shuffle/parity
- **1,411** 件の GS1 corpus 入力と、native の厳密な URL/type/resource 検査
- 全 **102** 件の cross-port regression vector: FNC1 の literal-percent/GS、容量境界、Digital Link の dot 安全性、DPI と ECC の型
- native engine の unit、render parity/max-budget、API/SA、GS1、不正 wire、CLI の検査
- コピーした addon だけを使う新しい別プロジェクトでの import と実際の main-scene 実行、Godot による自前 PNG の復号、native Image の正確な RGBA bytes
- 実際に生成した PNG pixels と独立した Nayuki matrix に対する C++ と Java の独立 decode、SVG の直接 rasterization、data URL の往復変換

正確な gate 件数、固定した tool version、コマンドは `verification/README.md` と各生成レポートを参照してください。baseline 参照は公開再現可能な合成 fixture であり、private なプロジェクトやユーザーのデータではありません。

## Explicit parity differences

### NUL in text

Godot 4.3 は String の U+0000 を保持できず、4.7.2 は保持せずに置換します。native JSON を通すと警告が出る場合もあります。NUL を含む public text request は正確に 8 件です。`verification/fixtures/godot-host-deltas.json` は、それらの index と期待する型付き INVALID_INPUT 結果を固定します。これらも実行し、拒否した text request に対して行列一致は主張しません。

NUL を含むデータには byte Array/PackedByteArray を使ってください。埋込みゼロを含む binary 経路は、別途、損失なく保持することを確認します。UTF-8 helper、CLI、厳密な wire 境界は、host 変換前に NUL text を拒否します。アプリケーションが既に Godot に変更された String を作らせた場合、失われた元の文字を後から検出することはできません。

### GS1 profile

完全な現行 TypeScript oracle は、同じ過去入力 1,411 件を対象にします。この版では、以前に拒否した入力 77 件と IPv6 表記 3 件を、正確な受理結果の assertion によって復元します。残る差 168 件は、診断のみの 132 件、意図的な拒否 34 件（厳密な percent/UTF-8/NUL の 20 件、Unicode/IDNA host の 12 件、primary-context 検査 2 件）、安全な dot-query builder の受理 2 件です。各例外は独立に固定し、候補から期待値を生成しません。共有 GS1 操作 49 件もすべて残し、authority の受理復元 18 件と、残る明示的な例外 3 件を含みます。`docs/gs1.md` を参照してください。WHATWG/UTS46 全体や GS1 全体の認証は主張しません。

### Java default-scale detector characterization

The default PNG scale is 8. Actual PNGs at that scale are decoded and checked with C++. Java ZXing's strict cross-decoder suite uses scale 3, separately from a scale-8 diagnostic. In the fixed ten-case diagnostic, nine candidate/independent-reference pairs decode; `alphanumeric-L-0` yields paired NotFound at scale 8. Its exact matrices and scale-3 pixels still decode, and C++ validates the scale-8 payload/pixels. Only that exact paired outcome is accepted; arbitrary failures are not converted into success. A detector rejection is not reported as successful decoding.

### Host and CLI conventions

native boolean は厳密な Godot bool です。Perl 固有の flagged/tied/blessed scalar の動作は適用しません。GDScript には言語の例外がないため、想定されるエラーは Dictionary を返します。CLI の binary PNG には `--output` が必要で、file 引数は `-` を stdin に使いません。facade は実質的に同じ QR 機能を提供します。

## Local/CI execution

レビュー可能な source の変更が完了してから manifest を作成してください。

```sh
python3 script/prepare_ci.py manifest
python3 script/prepare_ci.py stage --output /tmp/specqr-gdscript-stage
python3 /tmp/specqr-gdscript-stage/script/verify_native.py \
  --godot /path/to/Godot_v4.3-stable_linux.x86_64 \
  --expect-version 4.3 --output /tmp/specqr-gdscript-evidence
```

新しい出力 directory を使ってください。runner は、engine 用に書込み可能な task-local の HOME/XDG directory を用意し、protocol stdout には `--headless --no-header` を使います。Godot 4.3 の `--quiet` は script の print 出力も抑止するため、別のレポートファイルを書く consumer scene だけに使用します。CI workflow は公式の両 lane と独立 decoder gate を実行し、両方の成功を要求します。

公開完了には、GitHub 上の正確なレビュー済み SHA、その SHA に対する必須 CI の成功、新しい public consumer 検証が必要です。ローカルの部分的な実行、古い SHA でのテスト成功、source への結び付けがないレポート、platform 検査が阻止された状態は完了ではありません。GitHub での source 公開は、Asset Library、package registry、tag/release の公開を意味しません。
