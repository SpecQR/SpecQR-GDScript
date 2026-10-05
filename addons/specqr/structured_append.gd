extends RefCounted

const E = preload("error.gd")
const T = preload("tables.gd")
const S = preload("segments.gd")
const O = preload("optimizer.gd")
const A = preload("api.gd")

static func _range(value, lo, hi):
	return E.is_integer(value) and value >= lo and value <= hi

static func _xor(bytes):
	var parity = 0
	for byte in bytes: parity ^= int(byte)
	return parity

static func _octets(segment):
	return S.text(segment) if S.is_binary(segment) else S.encode_utf8(S.text(segment))

static func calculate_structured_append_parity(input):
	if typeof(input) == TYPE_ARRAY or typeof(input) == TYPE_PACKED_BYTE_ARRAY:
		var segment = S.byte_segment(input)
		return segment if E.is_error(segment) else _xor(S.text(segment))
	var chars = S.strict_text(input)
	if E.is_error(chars): return chars
	return _xor(S.encode_utf8(input))

static func _manual(values, budget=S.MAX_PAYLOAD_UNITS):
	if typeof(values) != TYPE_ARRAY or values.is_empty(): return E.error("INVALID_INPUT", "Structured Append needs nonempty manual segments")
	if values.size() > S.MAX_MANUAL_SEGMENTS: return E.error("DATA_TOO_LONG", "Too many manual segments")
	# Bound known payload containers before normalization takes owned copies.
	var preflight_units = 0
	for value in values:
		if typeof(value) == TYPE_DICTIONARY and typeof(value.get("mode")) == TYPE_STRING and value.mode in ["numeric", "alphanumeric", "kanji", "byte"]:
			var data = value.get("data")
			var units = data.length() if typeof(data) == TYPE_STRING else (data.size() if typeof(data) == TYPE_ARRAY or typeof(data) == TYPE_PACKED_BYTE_ARRAY else 0)
			if units > mini(S.MAX_PAYLOAD_UNITS, budget) - preflight_units: return E.error("DATA_TOO_LONG", "Manual payload exceeds Structured Append capacity")
			preflight_units += units
	var segments = S.normalize_segments(values)
	if E.is_error(segments): return segments
	var units = 0
	for segment in segments:
		if segment.mode == "fnc1": return E.error("INVALID_GS1", "Structured Append cannot be combined with FNC1")
		if S.is_control(segment): return E.error("INVALID_MODE", "Structured Append cannot include manual control segments")
		var n = S.byte_count(segment) if S.is_binary(segment) else S.character_count(segment)
		if n == 0: return E.error("INVALID_INPUT", "Structured Append requires nonempty data segments")
		if n > mini(S.MAX_PAYLOAD_UNITS, budget) - units: return E.error("DATA_TOO_LONG", "Manual payload exceeds Structured Append capacity")
		units += n
	return segments

static func calculate_structured_append_segments_parity(values):
	var segments = _manual(values)
	if E.is_error(segments): return segments
	var parity = 0
	for segment in segments: parity ^= _xor(_octets(segment))
	return parity

static func _capacity(options, version):
	return 8 * T.data_codeword_count(version, options.errorCorrectionLevel)

static func _capacity_version(options):
	return options.version if options.version != 0 else options.maxVersion

static func _unit_budget(options, maximum):
	return maximum * int(maxi(0, _capacity(options, _capacity_version(options)) - 20) * 3 / 10)

static func _check(options, maximum, manual, detail, results):
	if not _range(maximum, 2, 16): return E.error("INVALID_MODE", "maxSymbols must be between 2 and 16")
	if typeof(detail) != TYPE_STRING or typeof(results) != TYPE_STRING or not detail in ["summary", "full"] or not results in ["output", "diagnostics"]: return E.error("INVALID_INPUT", "Invalid Structured Append diagnostic detail")
	if options.gs1: return E.error("INVALID_GS1", "Structured Append cannot be combined with gs1")
	if options.fnc1 or options.eciAssignment >= 0 or options.fnc1Second != "" or options.structuredAppend != null: return E.error("INVALID_MODE", "Structured Append owns its header and cannot include other controls")
	if options.boostErrorCorrection: return E.error("INVALID_MODE", "Structured Append does not support ECC boosting")
	if manual and (options.mode != "auto" or not options.optimizeSegments): return E.error("INVALID_MODE", "Manual Structured Append preserves caller modes")
	return null

static func _numeric_bits(n):
	return int(n / 3) * 10 + [0, 4, 7][n % 3]

static func _payload_bits(mode, n, nb):
	if mode == "numeric": return _numeric_bits(n)
	if mode == "alphanumeric": return int(n / 2) * 11 + (n % 2) * 6
	if mode == "kanji": return n * 13
	return nb * 8

static func _segment_bits(mode, n, nb, version):
	var width = T.character_count_bits(version, mode)
	var count = nb if mode == "byte" else n
	if count >= (1 << width): return 1000000000
	return 4 + width + _payload_bits(mode, n, nb)

static func _offsets(chars):
	var offsets = [0]
	for c in chars: offsets.append(offsets[-1] + S.encode_utf8(c).size())
	return offsets

static func _input_source(value, options, maximum):
	var binary = typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_BYTE_ARRAY
	var version = _capacity_version(options)
	if binary:
		if value.size() > _unit_budget(options, maximum): return E.error("DATA_TOO_LONG", "Input exceeds Structured Append capacity")
		var segment = S.byte_segment(value)
		if E.is_error(segment): return segment
		var n = S.byte_count(segment)
		if n == 0: return E.error("INVALID_INPUT", "Structured Append needs at least two nonempty symbols")
		if options.mode != "auto" and options.mode != "byte": return E.error("INVALID_MODE", "Binary input requires byte mode")
		if n * 8 > maximum * maxi(0, _capacity(options, version) - 24 - T.character_count_bits(version, "byte")): return E.error("DATA_TOO_LONG", "Input exceeds Structured Append capacity")
		return {"binary": true, "manual": false, "data": S.text(segment), "length": n, "inputLength": n, "byteLength": n, "parity": _xor(S.text(segment))}
	if typeof(value) == TYPE_STRING and value.length() > _unit_budget(options, maximum): return E.error("DATA_TOO_LONG", "Input exceeds Structured Append capacity")
	var chars = S.strict_text(value)
	if E.is_error(chars): return chars
	var n = chars.size()
	if n == 0: return E.error("INVALID_INPUT", "Structured Append needs at least two nonempty symbols")
	if options.mode != "auto":
		var valid = S.new_segment(options.mode, value)
		if E.is_error(valid): return valid
	var bytes = S.encode_utf8(value)
	var width = 1000000
	if options.mode == "auto":
		for mode in ["numeric", "alphanumeric", "kanji", "byte"]: width = mini(width, T.character_count_bits(version, mode))
	else: width = T.character_count_bits(version, options.mode)
	var required = _numeric_bits(n) if options.mode == "auto" else _payload_bits(options.mode, n, bytes.size())
	if required > maximum * maxi(0, _capacity(options, version) - 24 - width): return E.error("DATA_TOO_LONG", "Input exceeds Structured Append capacity")
	return {"binary": false, "manual": false, "data": value, "characters": chars, "offsets": _offsets(chars), "length": n, "inputLength": n, "byteLength": bytes.size(), "parity": _xor(bytes)}

static func _segment_source(values, options, maximum):
	var segments = _manual(values, _unit_budget(options, maximum))
	if E.is_error(segments): return segments
	var version = _capacity_version(options)
	var source = {"manual": true, "binary": false, "segments": segments, "inputLength": segments.size(), "length": 0, "byteLength": 0, "parity": 0, "descriptors": []}
	var bits = 0
	for i in range(segments.size()):
		var segment = segments[i]
		var n = S.byte_count(segment) if S.is_binary(segment) else S.character_count(segment)
		var bytes = _octets(segment)
		var size = bytes.size()
		var split = n if segment.mode == "byte" else 1
		var d = {"segment": segment, "sourceIndex": i, "splitStart": source.length, "splitCount": split, "byteStart": source.byteLength, "byteLength": size}
		if segment.mode == "byte" and not S.is_binary(segment): d.offsets = _offsets(S.strict_text(S.text(segment)))
		source.descriptors.append(d)
		source.length += split
		source.byteLength += size
		source.parity ^= _xor(bytes)
		bits += 4 + T.character_count_bits(version, segment.mode) + _payload_bits(segment.mode, n, size)
	if bits > maximum * maxi(0, _capacity(options, version) - 20): return E.error("DATA_TOO_LONG", "Segments exceed Structured Append capacity")
	return source

static func _input_slice(source, start, n):
	return source.data.slice(start, start + n) if source.binary else source.data.substr(start, n)

static func _input_byte_length(source, start, n):
	return n if source.binary else source.offsets[start + n] - source.offsets[start]

static func _ranges(source, start, n):
	var finish = start + n
	var low = 0
	var high = source.descriptors.size()
	while low < high:
		var mid = low + int((high - low) / 2)
		var d = source.descriptors[mid]
		if d.splitStart + d.splitCount <= start: low = mid + 1
		else: high = mid
	var ranges = []
	for i in range(low, source.descriptors.size()):
		var d = source.descriptors[i]
		if d.splitStart >= finish: break
		var overlap = maxi(start, d.splitStart)
		ranges.append([i, overlap - d.splitStart, mini(finish, d.splitStart + d.splitCount) - overlap])
	return ranges

static func _range_bytes(d, start, n):
	if d.segment.mode != "byte": return [d.byteStart, d.byteLength]
	if not S.is_binary(d.segment): return [d.byteStart + d.offsets[start], d.offsets[start + n] - d.offsets[start]]
	return [d.byteStart + start, n]

static func _source_bits(source, start, n, options, version):
	var capacity = _capacity(options, version)
	if source.manual:
		var required = 20
		for p in _ranges(source, start, n):
			var d = source.descriptors[p[0]]
			var nb = _range_bytes(d, p[1], p[2])[1]
			var length = p[2] if d.segment.mode == "byte" else S.character_count(d.segment)
			required += _segment_bits(d.segment.mode, length, nb, version)
			if required > capacity: break
		return required
	if _numeric_bits(n) > capacity - 20: return 1000000000
	if source.binary: return 20 + _segment_bits("byte", n, n, version)
	if options.mode != "auto": return 20 + _segment_bits(options.mode, n, _input_byte_length(source, start, n), version)
	if options.optimizeSegments:
		var tracker = O.new_segment_optimization_tracker(version, options.allowKanji)
		if E.is_error(tracker): return tracker
		var required = 0
		for i in range(start, start + n):
			required = O._append_character_trusted(tracker, source.characters[i])
			if E.is_error(required): return required
			if required + 20 > capacity: break
		return required + 20
	var data = O.create_segments(_input_slice(source, start, n), "auto", version, false, -1, options.allowKanji)
	if E.is_error(data): return data
	for segment in data:
		if S.segment_count(segment) >= (1 << T.character_count_bits(version, segment.mode)): return 1000000000
	return 20 + S.segments_bit_length(data, version)

static func _largest_prefix(source, start, maximum, options, version):
	if not source.manual and not source.binary and options.mode == "auto" and options.optimizeSegments:
		var tracker = O.new_segment_optimization_tracker(version, options.allowKanji)
		if E.is_error(tracker): return tracker
		var capacity = _capacity(options, version) - 20
		for i in range(1, maximum + 1):
			var required = O._append_character_trusted(tracker, source.characters[start + i - 1])
			if E.is_error(required): return required
			if required > capacity: return i - 1
		return maximum
	var low = 1
	var high = maximum
	var result = 0
	var capacity = _capacity(options, version)
	while low <= high:
		var n = low + int((high - low) / 2)
		var required = _source_bits(source, start, n, options, version)
		if E.is_error(required): return required
		if required <= capacity:
			result = n
			low = n + 1
		else: high = n - 1
	return result

static func _attempt(source, options, version, maximum):
	var required = _source_bits(source, 0, source.length, options, version)
	if E.is_error(required): return required
	if required <= _capacity(options, version): return ["single", []]
	var ranges = []
	var start = 0
	while start < source.length:
		if ranges.size() == maximum: return ["long", []]
		var possible = source.length - start - (1 if ranges.is_empty() else 0)
		var n = _largest_prefix(source, start, possible, options, version)
		if E.is_error(n): return n
		if n <= 0: return ["long", []]
		ranges.append([start, n])
		start += n
	return ["ok" if ranges.size() >= 2 else "single", ranges]

static func _select(source, options, maximum):
	var lo = options.version if options.version != 0 else options.minVersion
	var hi = options.version if options.version != 0 else options.maxVersion
	var too_long = false
	for version in range(lo, hi + 1):
		var attempt = _attempt(source, options, version, maximum)
		if E.is_error(attempt): return attempt
		if attempt[0] == "ok": return [version, attempt[1], "fixed" if options.version != 0 else "auto-minimum"]
		if attempt[0] == "long": too_long = true
	if too_long: return E.error("DATA_TOO_LONG", "Input cannot be split into %s or fewer symbols in the selected version range" % maximum)
	return E.error("INVALID_INPUT", "Input fits in one symbol; use generate or a low-level Structured Append header")

static func _segment_chunk(source, start, n):
	var segments = []
	var first = -1
	var last = 0
	var byte_start = 0
	var byte_length = 0
	for p in _ranges(source, start, n):
		var d = source.descriptors[p[0]]
		var bytes = _range_bytes(d, p[1], p[2])
		if first < 0:
			first = d.sourceIndex
			byte_start = bytes[0]
		last = d.sourceIndex + 1
		byte_length += bytes[1]
		if d.segment.mode == "byte":
			var text = S.text(d.segment)
			var segment = S.byte_segment(text.slice(p[1], p[1] + p[2])) if S.is_binary(d.segment) else S.new_segment("byte", text.substr(p[1], p[2]))
			if E.is_error(segment): return segment
			segments.append(segment)
		else: segments.append(d.segment)
	return [segments, {"source_segment_start": first, "source_segment_end": last, "split_unit_start": start, "split_unit_length": n, "byte_start": byte_start, "byte_length": byte_length}]

static func _full_detail(source):
	var rows = []
	for d in source.descriptors:
		for unit in range(d.splitCount):
			var bytes = _range_bytes(d, unit, 1)
			rows.append({"source_segment_index": d.sourceIndex, "mode": d.segment.mode, "unit_start": unit if d.segment.mode == "byte" else 0, "unit_length": 1 if d.segment.mode == "byte" else S.character_count(d.segment), "byte_start": bytes[0], "byte_length": bytes[1]})
	return rows

static func _generate_source(source, options, maximum, detail, results):
	if E.is_error(source): return source
	var selected = _select(source, options, maximum)
	if E.is_error(selected): return selected
	var version = selected[0]
	var ranges = selected[1]
	var selection = selected[2]
	var total = ranges.size()
	var symbols = []
	var details = []
	for i in range(total):
		var start = ranges[i][0]
		var n = ranges[i][1]
		var chosen = options.duplicate(true)
		chosen.version = version
		chosen.minVersion = version
		chosen.maxVersion = version
		chosen.structuredAppend = S.structured_append_segment(i + 1, total, source.parity)
		var q
		var offset
		if source.manual:
			var chunk = _segment_chunk(source, start, n)
			if E.is_error(chunk): return chunk
			q = A.generate_segments(chunk[0], chosen)
			offset = chunk[1]
		else:
			q = A.generate(_input_slice(source, start, n), chosen)
			offset = {"input_start": start, "input_length": n, "byte_start": start if source.binary else source.offsets[start], "byte_length": _input_byte_length(source, start, n)}
		if E.is_error(q): return q
		symbols.append(q)
		var required = q.diagnostics.data_bit_length
		var row = {"index": i + 1, "total": total, "parity": source.parity, "sequence_index": i, "sequence_total": total - 1, "sequence_indicator": (i << 4) | (total - 1), "version": version, "error_correction_level": q.errorCorrectionLevel, "data_bit_length": required, "capacity_bits": _capacity(options, version), "remaining_bits": _capacity(options, version) - required, "mask_pattern": q.maskPattern}
		row.merge(offset)
		details.append(row)
	var warnings = []
	if total == maximum: warnings.append({"code": "STRUCTURED_APPEND_MAX_SYMBOLS_NEAR_LIMIT", "severity": "info", "message": "The set uses the configured maximum number of symbols.", "details": {"total": total, "max_symbols": maximum}})
	if results == "diagnostics": warnings.append({"code": "STRUCTURED_APPEND_DECODER_SUPPORT_VARIES", "severity": "info", "message": "Decoder APIs vary in how they expose Structured Append metadata.", "details": {"total": total}})
	var reason = "Version %s was requested explicitly." % version if selection == "fixed" else "Version %s is the smallest version in %s..%s that can split the payload into %s symbols." % [version, options.minVersion, options.maxVersion, total]
	var d = {"version": version, "error_correction_level": options.errorCorrectionLevel, "version_selection": selection, "version_selection_reason": reason, "total": total, "parity": source.parity, "byte_length": source.byteLength, "input_length": source.inputLength, "max_symbols": maximum, "split_strategy": "segment-boundary-byte-chunk" if source.manual else "greedy-largest-fitting", "symbols": details, "warnings": warnings}
	if source.manual:
		d.segment_count = source.segments.size()
		d.split_unit_count = source.length
		d.split_units_detail = detail
		if detail == "full": d.split_units = _full_detail(source)
	return {"symbols": symbols, "total": total, "parity": source.parity, "inputLength": source.inputLength, "byteLength": source.byteLength, "diagnostics": d}

static func generate_structured_append(input, raw=null, maximum=16, include_diagnostics=false):
	if typeof(include_diagnostics) != TYPE_BOOL: return E.error("INVALID_INPUT", "Diagnostics must be a boolean")
	var options = A.normalize_options(raw)
	if E.is_error(options): return options
	var results = "diagnostics" if include_diagnostics else "output"
	var valid = _check(options, maximum, false, "summary", results)
	if E.is_error(valid): return valid
	maximum = int(maximum)
	return _generate_source(_input_source(input, options, maximum), options, maximum, "summary", results)

static func generate_segments_structured_append(segments, raw=null, maximum=16, include_diagnostics=false, detail="summary", results=null):
	if typeof(include_diagnostics) != TYPE_BOOL: return E.error("INVALID_INPUT", "Diagnostics must be a boolean")
	if results == null or (typeof(results) == TYPE_STRING and results.is_empty()): results = "diagnostics" if include_diagnostics else "output"
	var options = A.normalize_options(raw)
	if E.is_error(options): return options
	var valid = _check(options, maximum, true, detail, results)
	if E.is_error(valid): return valid
	maximum = int(maximum)
	return _generate_source(_segment_source(segments, options, maximum), options, maximum, detail, results)

static func merge_structured_append_parts(parts):
	if typeof(parts) != TYPE_ARRAY or parts.is_empty() or parts.size() > 16: return E.error("INVALID_INPUT", "parts must contain 1..16 decoded mappings")
	var ordered = {}
	var summaries = {}
	var total = -1
	var parity = -1
	var kind = ""
	var nb = 0
	var actual = 0
	var units = 0
	for part in parts:
		if typeof(part) != TYPE_DICTIONARY: return E.error("INVALID_INPUT", "Part must be a dictionary")
		if not _range(part.get("index"), 1, 16) or not _range(part.get("total"), 2, 16) or not _range(part.get("parity"), 0, 255): return E.error("INVALID_INPUT", "Invalid Structured Append metadata")
		var index = int(part.index)
		var t = int(part.total)
		var p = int(part.parity)
		if index > t: return E.error("INVALID_INPUT", "Index exceeds total")
		if total >= 0 and t != total: return E.error("INVALID_INPUT", "Structured Append total mismatch")
		if parity >= 0 and p != parity: return E.error("INVALID_INPUT", "Structured Append parity mismatch")
		if ordered.has(index): return E.error("INVALID_INPUT", "Duplicate Structured Append index %s" % index)
		var data = part.get("data")
		var typ
		var n
		var size
		var checksum
		var owned
		if typeof(data) == TYPE_ARRAY or typeof(data) == TYPE_PACKED_BYTE_ARRAY:
			if data.size() > S.MAX_PAYLOAD_UNITS - units: return E.error("DATA_TOO_LONG", "Merged input exceeds the resource limit")
			var segment = S.byte_segment(data)
			if E.is_error(segment): return segment
			typ = "binary"
			n = S.byte_count(segment)
			size = n
			owned = S.text(segment)
			checksum = _xor(owned)
		else:
			if typeof(data) == TYPE_STRING and data.length() > S.MAX_PAYLOAD_UNITS - units: return E.error("DATA_TOO_LONG", "Merged input exceeds the resource limit")
			var chars = S.strict_text(data)
			if E.is_error(chars): return chars
			var bytes = S.encode_utf8(data)
			typ = "string"
			n = chars.size()
			size = bytes.size()
			checksum = _xor(bytes)
			owned = data
		if n > S.MAX_PAYLOAD_UNITS - units: return E.error("DATA_TOO_LONG", "Merged input exceeds the resource limit")
		units += n
		if kind != "" and kind != typ: return E.error("INVALID_INPUT", "Parts must not mix text and binary data")
		total = t
		parity = p
		kind = typ
		nb += size
		actual ^= checksum
		ordered[index] = owned
		summaries[index] = {"index": index, "total": total, "parity": parity, "data_type": kind, "byte_length": size}
	var missing = []
	for i in range(1, total + 1):
		if not ordered.has(i): missing.append(str(i))
	if not missing.is_empty(): return E.error("INVALID_INPUT", "Missing Structured Append indexes: " + ", ".join(missing))
	if parts.size() != total: return E.error("INVALID_INPUT", "Part count does not match total")
	if actual != parity: return E.error("INVALID_INPUT", "Structured Append parity check failed")
	var merged = "" if kind == "string" else []
	var rows = []
	for i in range(1, total + 1):
		if kind == "string": merged += ordered[i]
		else: merged.append_array(ordered[i])
		rows.append(summaries[i])
	return {"data": merged, "total": total, "parity": parity, "parts": rows, "diagnostics": {"part_count": total, "total": total, "parity": parity, "data_type": kind, "byte_length": nb, "missing": [], "duplicate": [], "parity_check": {"expected": parity, "actual": actual, "matches": true}}}
