# Verification profile

This directory contains public synthetic fixtures, provenance, the explicit Godot
host limitation, and checksum pins for the reviewed Linux x86-64 engines. It
contains no user messages, private logs, credentials, or production payloads.

## Engines and process contract

The floor is official Godot 4.3 stable; current stable at review (2026-10-05) is
Godot 4.7.2. `script/install_godot.py` verifies the pinned official SHA512 checksum
manifest, the archive's SHA512 and SHA256, its exact member inventory, and the
extracted engine SHA256. Tools install outside the source tree.

Native programs run with `--headless --no-header --path ... --script ... --`.
Godot 4.3 `--quiet` suppresses application JSON stdout as well as the engine
header, and that version has no `Engine.print_to_stdout` setter. No header or
error filtering is used. Every response is strict JSON, each request has exactly
one response, and exit status, stderr, trailing output, timeout, source inventory,
input/output digests, and final process shutdown are checked. Normal verification
requires zero stderr. Tests that intentionally provoke a child-process failure
record and reject that failure; they are not product passes.

Each runtime has isolated writable HOME and XDG directories outside source.
Godot-created `.godot` cache directories and `.gd.uid` sidecars are excluded from
the source inventory; they are generated engine metadata, not shipped library
source. Actual GDScript and fixture bytes remain source-bound. Native library
modules do not invoke another language or process. Python, Perl/TypeScript/Nim
oracle generation utilities, SVG rasterizers and ZXing are development-only.

## Complete checked corpus

- Public: 5,610 requests (3,028 generation; 1,920 estimates; 640 capacities;
  22 structured-append sets), including 1,280 independently generated Nayuki
  version/ECC/mask matrices
- Internal: 4,576 requests (4,320 raw-codeword matrices, 255 RS degrees, one
  exhaustive 65,536-product GF(256) result)
- Shared regression corpus: exactly 102 percent/FNC1 vectors, with independently
  derived 70 successes, 10 forced-alpha errors and 22 capacity errors, plus manual
  semantics, Digital Link, current-TypeScript authority compatibility, malformed
  authority, print-DPI and ECC boundary checks
- GS1: all 1,411 unchanged historical requests against freshly executed current
  TypeScript outcomes: 1,243 matches and 168 explicit residuals (132 diagnostic,
  34 accepted-to-rejected, two safe-dot-query). All 80 restored cases are checked
  separately. Five diagnostic-order migrations use independent Nim witnesses.
- Native: core, GS1, rendering, structured append, malformed native Variants,
  ownership, cycles, UTF-8 scalar validity, NUL bytes, integer-vs-boolean types,
  diagnostics isolation, and shuffled structured-append merges
- Real subprocess failure controls: late stderr, nonzero exit, extra stdout,
  duplicate/nonfinite JSON, timeout, missing output, source mutation, malformed
  decoder records and invalid PNG framing cannot become a pass. Independent GS1
  positives also reject blanket-error false-pass controls and unexpected fields.

The fixed public FNC1 overlay applies only to eight current-TypeScript corrections
and binds each original request/expected result. A separate eight-case Godot NUL
host overlay binds exact public fixture indices 2624–2631 and records a typed
`INVALID_INPUT` rejection rather than pretending that an altered string matched.
Godot 4.3 drops embedded U+0000 from strings; Godot 4.7.2 substitutes U+FFFD. Binary
Array/PackedByteArray input preserves every byte including zero and is tested.
No fixture is skipped. The floor's fgets-based test adapter is fed ASCII JSON
escapes, so 1,023-byte input chunks never split UTF-8 scalars; current Godot uses
its native raw stdin byte API. This adapter is a test protocol, not the library's
public text-input API.

## Independent output checks

The default renderer scale is 8. ZXing-C++ 3.1.1 decodes actual emitted PNGs at
that scale, including implicit-default versus explicit-scale equality. The Java
3.5.4 strict detector suite uses actual PNGs at scale 3 and has no matrix fallback,
PURE_BARCODE bypass, or tolerated failures. Structured-append headers, payload
bytes, parity, ECI and GS1 identifiers are checked separately.

A separate ten-case Java scale-8 characterization pins exactly one known
`NotFoundException` pair (`alphanumeric-L-0`) and nine successful pairs. Each
candidate is compared to an independently rendered identical-pixel PNG. All ten
have positive matrix, scale-3 PNG and C++ controls. The rejected pair is reported
as rejected and is never counted as successful PNG detection.

SVG bytes/data URLs and raster output are separately verified with an independent
rasterizer and decoder. Reusable receipts bind actual source, engine and decoder
bytes, command lines, exact counts, process exits, stderr and input/output hashes.

The unchanged shared GS1 inputs are all exercised through 49 independently
recorded current-TypeScript operations, with exactly three explicit native
overlays: two safe-dot builders and one malformed-host diagnostic. Six accepted
IPv4 aliases produce 18 positive authority checks; the remaining malformed
example.0x input retains all three rejection checks. See `gs1/README.md` for
complete source pins and exact residual categories.
