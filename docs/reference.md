# English API reference

## Runtime and installation

SpecQR 0.1.0 is native GDScript for the standard Godot 4.3+ engine. Godot is the required host, not an optional development dependency. No external QR package, JavaScript runtime, FFI, GDExtension, editor plugin or .NET runtime is used. Copy the complete `addons/specqr` directory into a project and preload `res://addons/specqr/specqr.gd`. The checked Linux x86-64 engines are official 4.3 and 4.7.2. Other operating systems and Web/mobile exports are not claimed as tested.

All public facade methods are static. Successful values are ordinary Dictionaries, Arrays, Strings, PackedByteArrays or native Images, as documented below. Expected failures return an error Dictionary; use `QR.is_error(result)` before consuming it. Dictionary keys may be String or StringName (including native dot-created keys) and are normalized to owned String keys at option and diagnostic-copy boundaries. Other key types and duplicate normalized keys are rejected; values keep the strict contracts below. Unknown option names are rejected. Public segment constructors and generation copy user payload storage; result Dictionaries are mutable, so treat returned results as owned values.

## Text, bytes, errors

Text is a Godot Unicode `String`. Raw bytes are an Array of numeric integers in 0..255 or a PackedByteArray. `new_segment("byte", text)` means UTF-8 text; `byte_segment(bytes)` is opaque binary. `encode_utf8(text)` returns a byte Array. `decode_utf8(bytes)` performs strict shortest-form UTF-8 decoding and rejects surrogates, values above U+10FFFF, truncated sequences and NUL.

Godot String cannot preserve U+0000. This limitation cannot be fixed after the host has already removed or replaced it. The CLI, explicit UTF-8 decoder and JSON test boundary reject NUL rather than silently modifying it. All 256 byte values, including zero, are supported losslessly through binary input. No fixture is silently removed for this host difference.

Integer settings accept Godot `int` or finite integral `float` values within their stated bounds, never numeric-looking strings or booleans. Boolean settings require `bool`. ECI's documented boolean alias is an exception: `eci: true` means assignment 26 and false means absent. ECI labels the encoding; it does not transcode data.

Error fields: `error: "SpecQRError"`, `isSpecQRError: true`, `code`, `message`; GS1 errors additionally have `detailCode`. Codes include `INVALID_INPUT`, `INVALID_MODE`, `INVALID_ECC_LEVEL`, `INVALID_VERSION`, `INVALID_ECI`, `INVALID_COLOR`, `INVALID_OUTPUT`, `INVALID_GS1`, `DATA_TOO_LONG`, and CLI `IO_ERROR`. Message wording is informative, not a compatibility key.

## Generation and planning

- `generate(text_or_bytes, options = null)`
- `generate_segments(segments, options = null)` preserves explicit boundaries
- `plan(text_or_bytes, options = null)` and alias `estimate`
- `plan_segments(segments, options = null)` and alias `analyze_segments`
- `get_capacity(version, ecc = "M", mode = "", control_bits = 0)`; a Dictionary with `version`, `errorCorrectionLevel`/`errorCorrection`, `mode`, `controlBits` is also accepted
- `diagnostics(result)` returns a checked independent JSON-compatible snapshot
- `size(qr)`, `module_at(qr, x, y)` use zero-based coordinates

QR result: `matrix` (square 0/1 Arrays), `version`, `maskPattern`, `errorCorrectionLevel`, `dataCodewords`, `codewords`, `segments`, `options`, `diagnostics`.

Plan: `ok`, `version`, `capacityVersion`, `errorCorrectionLevel`, `requestedErrorCorrectionLevel`, `boostedErrorCorrection`, `dataBitLength`, `capacityBits`, `remainingBits`, `segments`, `diagnostics`. A valid but non-fitting automatic plan has `ok=false`, `version=0`; `capacityVersion` gives the final tested capacity. Planning builds no codewords or matrix. Generation returns `DATA_TOO_LONG` if the selected range does not fit.

### Options

| Key | Default | Contract |
| --- | --- | --- |
| errorCorrectionLevel | M | Exactly L, M, Q or H |
| version | 0 | 0 or `"auto"`; fixed 1..40 |
| minVersion, maxVersion | 1, 40 | Ordered automatic search bounds |
| maskPattern | -1 | -1 or `"auto"`; fixed 0..7 |
| mode | auto | auto, numeric, alphanumeric, byte, kanji |
| optimizeSegments | true | Minimum-bit mixed-mode segmentation |
| allowKanji | true | Kanji in automatic optimization |
| boostErrorCorrection | false | Increase ECC without increasing version |
| eciAssignment | -1 | Absent -1, or 0..999999 |
| gs1, fnc1 | false | Validated GS1 or unvalidated FNC1 first position |
| fnc1Second | empty String | Two ASCII digits or one Latin letter |
| structuredAppend | null | Header with index, total, parity |
| margin, scale | 4, 8 | Margin 0..1e9; scale 1..1e9, integral |
| foreground, background | #000000, #ffffff | Safe hexadecimal or simple ASCII CSS color |
| printDpi | null | Finite positive number with finite positive geometry |

`errorCorrection` aliases `errorCorrectionLevel`; conflicts fail. `eci` accepts numeric assignment or the boolean alias. `encoding` supports only case-insensitive `utf-8`. `output` accepts matrix/svg/svg-data-url/png/png-data-url for compatibility but does not change the generation result type; call a renderer explicitly. `diagnostics` is validated as boolean; diagnostic information remains on results.

## Data and control segments

Constructors: `numeric(text)`, `alphanumeric(text)`, `kanji(text)`, `new_segment(mode,text)`, `byte_segment(bytes)`, `eci(assignment)`, `fnc1()`, `fnc1_second(indicator)`, `structured_append_segment(index,total,parity)`.

Inspection: `mode`, `is_control`, `is_binary`, `text`, `logical_bytes`, `segment_count`/`count`, `character_count`, `byte_count`, `assignment_number`, `application_indicator`, `application_indicator_codeword`, `index`, `total`, `parity`, `bit_length(segment,version)`, `bits(segment,version)`, `normalize_segments`, `segments_bit_length`, `segments_bits`.

Controls obey ordering and uniqueness rules; control families cannot be combined. SA index is one-based and total is 2..16. Manual high-level GS1 options are rejected; use an explicit `fnc1()` segment. Kanji uses the checked-in 6,953-pair mapping from the pinned SpecQR baseline, independent of host codecs.

High-level FNC1 treats literal `%` as data and U+001D as separator. Alphanumeric literal percent becomes `%%`; the automatic optimizer compares the escaped alternative against lossless byte encoding. Forced alphanumeric with GS is rejected. Manual alphanumeric segments already contain the caller's QR FNC1 representation: `%` separator and `%%` literal percent. Manual byte segments stay opaque.

## Rendering and native Image

`to_svg`, `to_png`, `to_pixels`, `to_svg_data_url`, `to_png_data_url`, `to_image` accept a QR result or QR-sized matrix (21..177, valid QR dimensions), plus optional render-only options. The override keys are only `margin`, `scale`, `foreground`, `background`; when an override is provided it uses defaults for omitted render keys.

SVG is ASCII text. PNG is PackedByteArray with RGBA8, filter 0, stored DEFLATE blocks and scratch CRC32/Adler32. `to_pixels` returns `{width,height,pixels}`, where pixels is a row-major RGBA PackedByteArray. `to_image` creates an ordinary Godot Image from these exact pixels; PNG encoding is not delegated to Godot. Use binary `FileAccess.store_buffer` for PNG.

Raster colors support #rgb, #rgba, #rrggbb, #rrggbbaa, black, white and transparent. Other safe ASCII CSS names are SVG-only; diagnostics report unknown contrast. `parse_color(color, strict=true)`, `contrast_ratio(rgba,rgba)` and `render_dimensions(qr_or_matrix, options=null, dpi=null)` are available. DPI is diagnostic physical geometry, not an embedded PNG pHYs field.

Limits: 1,000,000 payload units; 16,384 manual segments; 7,089 scalars for optimized single-symbol input; 4,194,304 raster pixels and side at most 2048; 8 MiB SVG characters; 32 MiB data URL characters. QR's actual symbol capacity is a separate, much smaller bound. Invalid and oversized geometry is rejected before raster allocation.

## Structured Append

`generate_structured_append(input, options=null, maximum=16, include_diagnostics=false)` returns `{symbols,total,parity,inputLength,byteLength,diagnostics}`. All symbols share version/ECC and may choose different masks. Automatic selection finds the smallest version permitting 2..16 symbols. Text splits on Unicode scalar boundaries; binary splits on bytes. Parity is XOR of original UTF-8 or opaque bytes.

`generate_segments_structured_append(segments, options=null, maximum=16, include_diagnostics=false, detail="summary", results=null)` keeps non-byte segments indivisible and subdivides byte segments at appropriate scalar/byte boundaries. `detail="full"` includes full split-unit diagnostics; `results` may be `"output"` or `"diagnostics"`.

High-level SA rejects empty/single-symbol input, existing SA headers, ECI/FNC1/GS1 and ECC boosting. Low-level SA headers remain available for caller-managed sets.

`merge_structured_append_parts(parts)` accepts decoded `{index,total,parity,data}` entries. It verifies complete unique indices, consistent metadata, homogeneous text/binary content and XOR parity, then returns `{data,total,parity,parts,diagnostics}`. It does not decode images or assume any decoder-specific extension. Parity helpers: `calculate_structured_append_parity`, `calculate_structured_append_segments_parity`.

## Low-level namespaces

The facade exposes `Core`, `Tables`, `Optimizer`, `Segments`, `Render`, `GS1`, `StructuredAppend`, `API`, `Error`. `Core` contains GF/RS/placement/mask methods, `Tables` QR capacities/alignment/count widths, and `Optimizer` includes the checked incremental tracker. Leading-underscore methods are implementation details. Normal applications should use the high-level facade.

GS1 URL normalization supports common ASCII HTTP(S) repairs, checked IPv4/IPv6 normalization and preserved userinfo; Unicode host IDNA/UTS46 and strict malformed percent/UTF-8/NUL handling remain explicit limitations. See [GS1 profile](gs1.md) and [verification contracts](verification.md). Diagnostics describe risk, not a guarantee that every camera or decoder will read every symbol.
