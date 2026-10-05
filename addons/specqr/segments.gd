extends RefCounted
## Owned data/control segments and their exact bit representation.
const E = preload("error.gd")
const T = preload("tables.gd")
const K = preload("kanji_data.gd")
const MAX_PAYLOAD_UNITS = 1000000
const MAX_MANUAL_SEGMENTS = 16384
const MAX_SINGLE_SYMBOL_CHARACTERS = 7089
const MAX_SINGLE_SYMBOL_DATA_BITS = 23648
const DATA_MODES = ["numeric", "alphanumeric", "kanji", "byte"]
const CONTROL_MODES = ["eci", "fnc1", "fnc1-second", "structured-append"]
const ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

static func strict_text(value):
	if typeof(value) != TYPE_STRING: return E.error("INVALID_INPUT", "Text must be a String")
	if value.length() > MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Text resource limit exceeded")
	if not E.string_valid(value): return E.error("INVALID_INPUT", "Text must contain Unicode scalars")
	var result = []
	for i in range(value.length()): result.append(value.substr(i, 1))
	return result

static func encode_utf8(value):
	var chars = strict_text(value)
	if E.is_error(chars): return chars
	var result = []
	for i in range(value.length()):
		var cp = value.unicode_at(i)
		if cp < 0x80: result.append(cp)
		elif cp < 0x800: result.append_array([0xc0 | (cp >> 6), 0x80 | (cp & 63)])
		elif cp < 0x10000: result.append_array([0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63)])
		else: result.append_array([0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63)])
	return result

static func kanji_code(character):
	return K.kanji_codepoint(character.unicode_at(0)) if typeof(character) == TYPE_STRING and character.length() == 1 else -1

static func can_encode_kanji(character):
	return kanji_code(character) >= 0

static func kanji_value(character):
	var code = kanji_code(character)
	if code < 0: return E.error("INVALID_MODE", "Character is not QR Kanji encodable")
	var adjusted = code - (0x8140 if code <= 0x9ffc else 0xc140)
	return (adjusted >> 8) * 0xc0 + (adjusted & 255)

static func alpha_value(character):
	return ALPHA.find(character) if typeof(character) == TYPE_STRING and character.length() == 1 and character.unicode_at(0) < 128 else -1

static func _base(segment_mode):
	return {"mode": segment_mode, "data": "", "binary": false, "characterCount": 0, "assignmentNumber": -1, "applicationIndicator": "", "index": -1, "total": -1, "parity": -1}

static func new_segment(segment_mode, value):
	if typeof(segment_mode) != TYPE_STRING or not segment_mode in DATA_MODES: return E.error("INVALID_MODE", "Expected a data mode")
	var chars = strict_text(value)
	if E.is_error(chars): return chars
	for c in chars:
		if segment_mode == "numeric" and not (c >= "0" and c <= "9"): return E.error("INVALID_MODE", "Numeric data must contain digits")
		if segment_mode == "alphanumeric" and alpha_value(c) < 0: return E.error("INVALID_MODE", "Invalid alphanumeric character")
		if segment_mode == "kanji" and not can_encode_kanji(c): return E.error("INVALID_MODE", "Invalid Kanji character")
	var result = _base(segment_mode)
	result.data = value
	result.characterCount = chars.size()
	return result

static func byte_segment(value):
	if typeof(value) != TYPE_ARRAY and typeof(value) != TYPE_PACKED_BYTE_ARRAY: return E.error("INVALID_INPUT", "Binary bytes must be an Array or PackedByteArray")
	if value.size() > MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Payload resource limit exceeded")
	var owned = []
	for b in value:
		if not E.in_range(b, 0, 255): return E.error("INVALID_INPUT", "Byte must be an integer in 0..255")
		owned.append(int(b))
	var result = _base("byte")
	result.data = owned
	result.binary = true
	return result

static func numeric(value): return new_segment("numeric", value)
static func alphanumeric(value): return new_segment("alphanumeric", value)
static func kanji(value): return new_segment("kanji", value)

static func eci(assignment):
	if not E.in_range(assignment, 0, 999999): return E.error("INVALID_ECI", "ECI assignment must be an integer in 0..999999")
	var result = _base("eci")
	result.assignmentNumber = int(assignment)
	return result

static func fnc1(): return _base("fnc1")

static func fnc1_second(indicator):
	if typeof(indicator) != TYPE_STRING: return E.error("INVALID_MODE", "FNC1 second indicator must be a String")
	var valid = indicator.length() == 2 and indicator[0] >= "0" and indicator[0] <= "9" and indicator[1] >= "0" and indicator[1] <= "9"
	if indicator.length() == 1: valid = (indicator >= "A" and indicator <= "Z") or (indicator >= "a" and indicator <= "z")
	if not valid: return E.error("INVALID_MODE", "FNC1 second indicator must be two ASCII digits or one Latin letter")
	var result = _base("fnc1-second")
	result.applicationIndicator = indicator
	return result

static func structured_append_segment(sequence_index, sequence_total, sequence_parity):
	if not E.in_range(sequence_index, 1, 16) or not E.in_range(sequence_total, 2, 16) or not E.in_range(sequence_parity, 0, 255) or sequence_index > sequence_total:
		return E.error("INVALID_MODE", "Invalid structured append header")
	var result = _base("structured-append")
	result.index = int(sequence_index)
	result.total = int(sequence_total)
	result.parity = int(sequence_parity)
	return result

static func _validated(segment):
	if typeof(segment) != TYPE_DICTIONARY: return E.error("INVALID_MODE", "Segment must be a Dictionary")
	var segment_mode = segment.get("mode")
	if typeof(segment_mode) != TYPE_STRING: return E.error("INVALID_MODE", "Segment mode must be a String")
	if segment_mode in DATA_MODES:
		var binary = segment.get("binary", false)
		if typeof(binary) != TYPE_BOOL: return E.error("INVALID_INPUT", "Segment binary must be a boolean")
		if binary and segment_mode != "byte": return E.error("INVALID_MODE", "Binary data requires byte mode")
		return byte_segment(segment.get("data")) if binary else new_segment(segment_mode, segment.get("data"))
	match segment_mode:
		"eci": return eci(segment.get("assignmentNumber"))
		"fnc1": return fnc1()
		"fnc1-second": return fnc1_second(segment.get("applicationIndicator"))
		"structured-append": return structured_append_segment(segment.get("index"), segment.get("total"), segment.get("parity"))
	return E.error("INVALID_MODE", "Uninitialized or unsupported segment")

static func validate_segment(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else null

static func mode(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.mode

static func is_control(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.mode in CONTROL_MODES

static func is_binary(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.binary

static func text(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.data

static func logical_bytes(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.data if checked.binary else encode_utf8(checked.data)

static func _count(segment):
	if segment.mode in CONTROL_MODES: return 0
	if segment.mode == "byte": return segment.data.size() if segment.binary else encode_utf8(segment.data).size()
	return segment.data.length()

static func segment_count(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else _count(checked)

static func count(segment): return segment_count(segment)

static func character_count(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.characterCount

static func byte_count(segment):
	var checked = _validated(segment)
	if E.is_error(checked): return checked
	if checked.mode == "kanji": return checked.data.length() * 2
	return checked.data.size() if checked.binary else encode_utf8(checked.data).size()

static func assignment_number(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.assignmentNumber

static func application_indicator(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.applicationIndicator

static func application_indicator_codeword(segment):
	var checked = _validated(segment)
	if E.is_error(checked): return checked
	if checked.mode != "fnc1-second": return -1
	return int(checked.applicationIndicator) if checked.applicationIndicator.length() == 2 else checked.applicationIndicator.unicode_at(0) + 100

static func index(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.index

static func total(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.total

static func parity(segment):
	var checked = _validated(segment)
	return checked if E.is_error(checked) else checked.parity

static func payload_bit_length(segment_mode, length):
	if not E.in_range(length, 0, 4 * MAX_PAYLOAD_UNITS): return E.error("INVALID_INPUT", "Payload count is outside supported range")
	var n = int(length)
	match segment_mode:
		"numeric": return int(n / 3) * 10 + [0, 4, 7][n % 3]
		"alphanumeric": return int(n / 2) * 11 + (n % 2) * 6
		"kanji": return n * 13
		"byte": return n * 8
	return E.error("INVALID_MODE", "Expected data mode")

static func _bit_length(segment, version):
	match segment.mode:
		"eci": return 12 if segment.assignmentNumber < 128 else 20 if segment.assignmentNumber < 16384 else 28
		"fnc1": return 4
		"fnc1-second": return 12
		"structured-append": return 20
	return 4 + T.character_count_bits(version, segment.mode) + payload_bit_length(segment.mode, _count(segment))

static func bit_length(segment, version):
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	var checked = _validated(segment)
	return checked if E.is_error(checked) else _bit_length(checked, version)

static func _append(output, value, width):
	for i in range(width - 1, -1, -1): output.append((int(value) >> i) & 1)

static func bits(segment, version):
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	var checked = _validated(segment)
	if E.is_error(checked): return checked
	var m = checked.mode
	var n = _count(checked)
	var length = _bit_length(checked, version)
	if not m in CONTROL_MODES and n >= (1 << T.character_count_bits(version, m)): return E.error("DATA_TOO_LONG", "Segment count does not fit")
	if length > MAX_SINGLE_SYMBOL_DATA_BITS: return E.error("DATA_TOO_LONG", "Segment exceeds single-symbol capacity")
	var indicator = {"numeric": 1, "alphanumeric": 2, "byte": 4, "kanji": 8, "eci": 7, "fnc1": 5, "fnc1-second": 9, "structured-append": 3}
	var output = []
	_append(output, indicator[m], 4)
	if m == "eci":
		var a = checked.assignmentNumber
		if a < 128: _append(output, a, 8)
		elif a < 16384:
			_append(output, 2, 2)
			_append(output, a, 14)
		else:
			_append(output, 6, 3)
			_append(output, a, 21)
	elif m == "fnc1-second": _append(output, application_indicator_codeword(checked), 8)
	elif m == "structured-append":
		_append(output, checked.index - 1, 4)
		_append(output, checked.total - 1, 4)
		_append(output, checked.parity, 8)
	elif m != "fnc1":
		_append(output, n, T.character_count_bits(version, m))
		var d = checked.data
		if m == "byte":
			for b in (d if checked.binary else encode_utf8(d)): _append(output, b, 8)
		elif m == "numeric":
			for i in range(0, d.length(), 3):
				var part = d.substr(i, 3)
				_append(output, int(part), [4, 7, 10][part.length() - 1])
		elif m == "alphanumeric":
			var i = 0
			while i + 1 < d.length():
				_append(output, alpha_value(d[i]) * 45 + alpha_value(d[i + 1]), 11)
				i += 2
			if i < d.length(): _append(output, alpha_value(d[i]), 6)
		else:
			for i in range(d.length()): _append(output, kanji_value(d[i]), 13)
	if output.size() != length: return E.error("INVALID_INPUT", "Inconsistent segment bit length")
	return output

static func normalize_segments(values):
	if typeof(values) != TYPE_ARRAY: return E.error("INVALID_INPUT", "Segments must be an Array")
	if values.size() > MAX_MANUAL_SEGMENTS: return E.error("DATA_TOO_LONG", "Manual segment resource limit exceeded")
	var output = []
	var controls = {}
	var units = 0
	for i in range(values.size()):
		var s = _validated(values[i])
		if E.is_error(s): return s
		units += s.data.size() if s.binary else s.characterCount
		if units > MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Manual payload resource limit exceeded")
		var m = s.mode
		if m in CONTROL_MODES:
			controls[m] = controls.get(m, 0) + 1
			if m != "eci" and (controls[m] > 1 or i != 0): return E.error("INVALID_GS1" if m == "fnc1" else "INVALID_MODE", "Control must be first and unique")
		output.append(s)
	if controls.size() > 1: return E.error("INVALID_GS1" if controls.has("fnc1") else "INVALID_MODE", "FNC1, ECI, and SA cannot be combined")
	return output

static func segments_bit_length(values, version):
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	var segments = normalize_segments(values)
	if E.is_error(segments): return segments
	var length = 0
	for s in segments: length += _bit_length(s, version)
	return length

static func segments_bits(values, version):
	var length = segments_bit_length(values, version)
	if E.is_error(length): return length
	if length > MAX_SINGLE_SYMBOL_DATA_BITS: return E.error("DATA_TOO_LONG", "Segments exceed single-symbol capacity")
	var segments = normalize_segments(values)
	if E.is_error(segments): return segments
	var output = []
	for s in segments:
		var encoded = bits(s, version)
		if E.is_error(encoded): return encoded
		output.append_array(encoded)
	return output

static func decode_utf8(bytes):
	if typeof(bytes) != TYPE_ARRAY and typeof(bytes) != TYPE_PACKED_BYTE_ARRAY: return E.error("INVALID_INPUT", "UTF-8 bytes must be an Array or PackedByteArray")
	if bytes.size() > 4 * MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Text resource limit exceeded")
	for b in bytes:
		if not E.in_range(b, 0, 255): return E.error("INVALID_INPUT", "UTF-8 bytes must be integers in 0..255")
	var output = ""
	var at = 0
	var scalars = 0
	while at < bytes.size():
		var lead = int(bytes[at])
		var cp = lead
		var width = 1
		if lead >= 0xc2 and lead <= 0xdf: width = 2; cp &= 31
		elif lead >= 0xe0 and lead <= 0xef: width = 3; cp &= 15
		elif lead >= 0xf0 and lead <= 0xf4: width = 4; cp &= 7
		elif lead >= 0x80: return E.error("INVALID_INPUT", "Malformed UTF-8 leading byte")
		if at + width > bytes.size(): return E.error("INVALID_INPUT", "Truncated UTF-8 sequence")
		for j in range(1, width):
			var b = int(bytes[at + j])
			if b < 0x80 or b > 0xbf: return E.error("INVALID_INPUT", "Malformed UTF-8 continuation")
			cp = (cp << 6) | (b & 63)
		if cp == 0: return E.error("INVALID_INPUT", "Godot String cannot preserve U+0000; use binary byte input")
		if cp > 0x10ffff or (cp >= 0xd800 and cp <= 0xdfff) or (width > 1 and cp < [0, 0, 0x80, 0x800, 0x10000][width]): return E.error("INVALID_INPUT", "UTF-8 must use shortest-form Unicode scalars")
		scalars += 1
		if scalars > MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Text resource limit exceeded")
		output += String.chr(cp)
		at += width
	return output
