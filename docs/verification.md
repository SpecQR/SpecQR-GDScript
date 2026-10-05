# Verification and release scope

## Runtime versus development tools

Runtime needs only the standard Godot engine, minimum 4.3. The validation lanes use official Linux x86-64 4.3 and current stable 4.7.2. Versions were checked against the [official archive](https://godotengine.org/download/archive/) and [Linux download page](https://godotengine.org/download/linux/). `script/install_godot.py` verifies official SHA512 release sums and pinned SHA256 binary/archive digests before running them. No downloaded QR encoder is part of the library.

Python, a development-only ZXing-C++ wheel, Java ZXing and librsvg are independent test tools. Optional Perl/Nim/TypeScript oracle generators are development-only. None is needed by applications using `addons/specqr`.

The initial public scope includes the encoding core, scratch SVG/PNG, exact RGBA pixels and native Godot Image. Local graphical display setup encountered a sandbox Unix-socket permission denial. Consequently no GPU readback is claimed or counted as a pass, and the optional Texture convenience adapter is not part of this initial public API. Native PNG decoding and Image byte equality remain required. Windows, macOS, mobile and Web export were not executed.

## Immutable and fail-closed gates

`SOURCE-SHA256.json` names and hashes every public source file except itself and generated engine/Python metadata. Verification stages a fresh copy, checks the exact inventory before and after, and binds reports to source bytes, actual interpreter hash and subprocess transcripts. Source changes invalidate the gate. Every protocol process requires the exact response count, clean exit and zero stderr; no extra lines, parse warnings, late failures or leftover responses are accepted.

The harness includes adversarial fake processes for extra output, nonzero final exit, stderr, malformed JSON, missing/oversized responses and timeouts. The JSON boundary is a strict bounded RFC8259 implementation: duplicate keys, malformed Unicode/UTF-8, nonfinite numbers and resource excess are rejected rather than delegated to Godot's permissive JSON behavior.

All coverage is retained:

- 5,610 public + 4,576 internal = **10,186** source-bound reference requests
- Exact all **1,280** version/ECC/mask combinations and **4,320** raw construction cases
- GF(256) table, Reed–Solomon degrees, capacity and optimizer cases, control segments, SA metadata/shuffle/parity
- **1,411** GS1 corpus inputs, plus native strict URL/type/resource checks
- All **102** cross-port regression vectors: FNC1 literal-percent/GS, capacity boundaries, Digital Link dot safety, DPI and ECC types
- Native engine unit, render parity/max-budget, API/SA, GS1, malformed wire and CLI checks
- Fresh separate-project import and real main-scene execution using only a copied addon, scratch PNG decoded by Godot, exact native Image RGBA bytes
- Independent C++ and Java decoding of actual generated PNG pixels and independent Nayuki matrices; direct SVG rasterization and data-URL round-trips

See `verification/README.md` and each generated report for exact gate counts, pinned tool versions and commands. Baseline references are publicly reproducible synthetic fixtures, not private project/user data.

## Explicit parity differences

### NUL in text

Godot 4.3 cannot preserve String U+0000; 4.7.2 replaces it rather than preserving it. Passing through native JSON can also emit warnings. Exactly eight public text requests contain NUL. `verification/fixtures/godot-host-deltas.json` pins their indices and expected typed INVALID_INPUT results. They still execute. No matrix-equality assertion is made for these rejected text requests.

Use byte Arrays/PackedByteArrays for NUL-containing data. Binary paths, including embedded zero, are separately proven lossless. The UTF-8 helper, CLI and strict wire boundary reject NUL text before host conversion. If an application has already asked Godot to create a modified String, the original lost character cannot be detected afterward.

### GS1 profile

The complete current-TypeScript oracle covers the same 1,411 historical inputs. This edition restores 77 formerly rejected input cases plus three IPv6 spellings, with exact positive assertions. The remaining 168 differences are 132 diagnostic-only cases, 34 intentional rejections (20 strict percent/UTF-8/NUL, 12 Unicode/IDNA hosts, two primary-context checks), and two safe dot-query builder acceptances. Each exception is pinned independently; no expectation is generated from the candidate. The 49 shared GS1 operations all remain, with 18 positive authority restorations and three explicit residual exceptions. See `docs/gs1.md`. Full WHATWG/UTS46 and comprehensive GS1 certification are not claimed.

### Java default-scale detector characterization

The default PNG scale is 8. Actual PNGs at that scale are decoded and checked with C++. Java ZXing's strict cross-decoder suite uses scale 3, separately from a scale-8 diagnostic. In the fixed ten-case diagnostic, nine candidate/independent-reference pairs decode; `alphanumeric-L-0` yields paired NotFound at scale 8. Its exact matrices and scale-3 pixels still decode, and C++ validates the scale-8 payload/pixels. Only that exact paired outcome is accepted; arbitrary failures are not converted into success. A detector rejection is not reported as successful decoding.

### Host and CLI conventions

Native booleans are strict Godot bools; Perl-specific flagged/tied/blessed scalar behavior is inapplicable. Expected errors are returned Dictionaries because GDScript has no language exceptions. CLI binary PNG requires `--output`; file arguments do not use `-` for stdin. The facade still provides the same substantive QR features.

## Local/CI execution

Create a manifest only after reviewable source changes are complete:

```sh
python3 script/prepare_ci.py manifest
python3 script/prepare_ci.py stage --output /tmp/specqr-gdscript-stage
python3 /tmp/specqr-gdscript-stage/script/verify_native.py \
  --godot /path/to/Godot_v4.3-stable_linux.x86_64 \
  --expect-version 4.3 --output /tmp/specqr-gdscript-evidence
```

Use fresh output directories. The runners arrange writable task-local HOME/XDG directories for the engine, and use `--headless --no-header` for protocol stdout. Godot 4.3 `--quiet` suppresses script print output too, so it is used only for consumer scenes that write a separate report file. The CI workflow runs both official lanes and the independent decoder gates, then requires both to succeed.

Publication completion requires the exact reviewed SHA on GitHub, successful required CI for that SHA, and fresh public consumer verification. A local partial run, a green test on an older SHA, a report without source bindings or a blocked platform check is not completion. GitHub source publication does not imply Asset Library, package-registry or tag/release publication.
