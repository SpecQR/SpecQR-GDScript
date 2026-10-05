extends RefCounted

const E = preload("error.gd")
const T = preload("tables.gd")
const S = preload("segments.gd")
const O = preload("optimizer.gd")
const C = preload("core.gd")
const R = preload("render.gd")
const G = preload("gs1.gd")
const MODES = ["numeric", "alphanumeric", "kanji", "byte"]
const LEVELS = ["L", "M", "Q", "H"]

static func _range(value, lo, hi):
	return E.is_integer(value) and value >= lo and value <= hi

# Native dictionary-dot syntax produces StringName keys. Normalize only those
# key types, without coercing values or traversing unrecognized payloads.
static func _normalize_option_keys(raw, allowed, label):
	if raw.size() > allowed.size(): return E.error("INVALID_INPUT", "Too many " + label + " keys")
	var result = {}
	for raw_key in raw:
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME: return E.error("INVALID_INPUT", label + " keys must be strings or StringNames")
		if raw_key.length() > 32: return E.error("INVALID_INPUT", "Unknown " + label + " key")
		var key = String(raw_key)
		if not key in allowed: return E.error("INVALID_INPUT", "Unknown " + label + " key: " + key)
		if result.has(key): return E.error("INVALID_INPUT", "Duplicate normalized " + label + " key: " + key)
		result[key] = raw[raw_key]
	return result

static func normalize_options(raw=null):
	if raw == null: raw = {}
	if typeof(raw) != TYPE_DICTIONARY: return E.error("INVALID_INPUT", "Options must be a dictionary")
	var o = {"errorCorrectionLevel": "M", "version": 0, "minVersion": 1, "maxVersion": 40, "maskPattern": -1, "mode": "auto", "optimizeSegments": true, "allowKanji": true, "boostErrorCorrection": false, "eciAssignment": -1, "gs1": false, "fnc1": false, "fnc1Second": "", "structuredAppend": null, "margin": 4, "scale": 8, "foreground": "#000000", "background": "#ffffff", "printDpi": null}
	var extra = ["eci", "errorCorrection", "encoding", "output", "diagnostics"]
	var allowed = o.keys()
	allowed.append_array(extra)
	raw = _normalize_option_keys(raw, allowed, "option")
	if E.is_error(raw): return raw
	for key in raw:
		if o.has(key): o[key] = raw[key]
	if raw.has("errorCorrection"):
		var level = T.level_index(raw.errorCorrection)
		if E.is_error(level): return level
		if raw.has("errorCorrectionLevel"):
			level = T.level_index(raw.errorCorrectionLevel)
			if E.is_error(level): return level
			if raw.errorCorrection != raw.errorCorrectionLevel: return E.error("INVALID_INPUT", "Error correction aliases must match")
		o.errorCorrectionLevel = raw.errorCorrection
	var valid = T.level_index(o.errorCorrectionLevel)
	if E.is_error(valid): return valid
	valid = T.validate_version(o.minVersion)
	if E.is_error(valid): return valid
	valid = T.validate_version(o.maxVersion)
	if E.is_error(valid): return valid
	if o.minVersion > o.maxVersion: return E.error("INVALID_VERSION", "minVersion must not exceed maxVersion")
	if typeof(o.version) == TYPE_STRING and o.version == "auto": o.version = 0
	if not _range(o.version, 0, 40): return E.error("INVALID_VERSION", "QR version must be between 0 and 40")
	if typeof(o.maskPattern) == TYPE_STRING and o.maskPattern == "auto": o.maskPattern = -1
	if not _range(o.maskPattern, -1, 7): return E.error("INVALID_INPUT", "Mask must be between -1 and 7")
	if typeof(o.mode) != TYPE_STRING or (o.mode != "auto" and not o.mode in MODES): return E.error("INVALID_MODE", "Unsupported data mode")
	for key in ["optimizeSegments", "allowKanji", "boostErrorCorrection", "gs1", "fnc1"]:
		if typeof(o[key]) != TYPE_BOOL: return E.error("INVALID_GS1" if key == "gs1" else "INVALID_INPUT", key + " must be a boolean")
	if not _range(o.eciAssignment, -1, 999999): return E.error("INVALID_ECI", "Invalid ECI assignment")
	if raw.has("eci"):
		var eci = raw.eci
		var number
		if typeof(eci) == TYPE_BOOL: number = 26 if eci else -1
		else:
			if not _range(eci, 0, 999999): return E.error("INVALID_ECI", "Invalid ECI assignment")
			number = int(eci)
		if raw.has("eciAssignment") and o.eciAssignment != number: return E.error("INVALID_ECI", "ECI aliases must match")
		o.eciAssignment = number
	if typeof(o.fnc1Second) != TYPE_STRING: return E.error("INVALID_MODE", "FNC1 second indicator must be a string")
	if o.fnc1Second != "":
		valid = S.fnc1_second(o.fnc1Second)
		if E.is_error(valid): return valid
	if o.structuredAppend != null:
		var sa = o.structuredAppend
		if typeof(sa) != TYPE_DICTIONARY: return E.error("INVALID_MODE", "Structured append must be a dictionary")
		if sa.has("mode") and (typeof(sa.mode) != TYPE_STRING or sa.mode != "structured-append"): return E.error("INVALID_MODE", "Structured append requires a header")
		o.structuredAppend = S.structured_append_segment(sa.get("index"), sa.get("total"), sa.get("parity"))
		if E.is_error(o.structuredAppend): return o.structuredAppend
	var families = int(o.gs1 or o.fnc1) + int(o.fnc1Second != "") + int(o.eciAssignment >= 0) + int(o.structuredAppend != null)
	if families > 1: return E.error("INVALID_GS1" if o.gs1 else "INVALID_MODE", "FNC1, ECI, and SA controls cannot be combined")
	if not _range(o.margin, 0, 1000000000): return E.error("INVALID_INPUT", "Invalid margin")
	if not _range(o.scale, 1, 1000000000): return E.error("INVALID_INPUT", "Invalid scale")
	valid = R.parse_color(o.foreground, false)
	if E.is_error(valid): return valid
	valid = R.parse_color(o.background, false)
	if E.is_error(valid): return valid
	if o.printDpi != null:
		if not E.is_number(o.printDpi) or o.printDpi <= 0: return E.error("INVALID_INPUT", "DPI must be positive")
		var mm = (177 + 2 * o.margin) * (float(o.scale) / o.printDpi * 25.4)
		if not is_finite(mm) or mm <= 0: return E.error("INVALID_INPUT", "DPI must produce finite positive print geometry")
	if raw.has("encoding") and (typeof(raw.encoding) != TYPE_STRING or raw.encoding.to_lower() != "utf-8"): return E.error("INVALID_INPUT", "Only UTF-8 encoding is supported")
	if raw.has("output") and (typeof(raw.output) != TYPE_STRING or not raw.output in ["matrix", "svg", "svg-data-url", "png", "png-data-url"]): return E.error("INVALID_OUTPUT", "Unsupported output")
	if raw.has("diagnostics") and typeof(raw.diagnostics) != TYPE_BOOL: return E.error("INVALID_INPUT", "diagnostics must be a boolean")
	for key in ["version", "minVersion", "maxVersion", "maskPattern", "eciAssignment", "margin", "scale"]: o[key] = int(o[key])
	return o

static func validate_options(raw=null):
	var o = normalize_options(raw)
	return o if E.is_error(o) else null

static func render_options(raw=null):
	var o = normalize_options(raw)
	if E.is_error(o): return o
	return {"margin": o.margin, "scale": o.scale, "foreground": o.foreground, "background": o.background}

static func get_capacity(version, level="M", mode="", control=0):
	if typeof(version) == TYPE_DICTIONARY:
		var o = _normalize_option_keys(version, ["version", "errorCorrectionLevel", "errorCorrection", "mode", "controlBits"], "capacity option")
		if E.is_error(o): return o
		for key in ["errorCorrection", "errorCorrectionLevel"]:
			if o.has(key):
				var check = T.level_index(o[key])
				if E.is_error(check): return check
		if o.has("errorCorrection") and o.has("errorCorrectionLevel") and o.errorCorrection != o.errorCorrectionLevel: return E.error("INVALID_INPUT", "Error correction aliases must match")
		level = o.get("errorCorrectionLevel", o.get("errorCorrection", "M"))
		mode = o.get("mode", "")
		control = o.get("controlBits", 0)
		version = o.get("version")
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	valid = T.level_index(level)
	if E.is_error(valid): return valid
	if typeof(mode) != TYPE_STRING: return E.error("INVALID_MODE", "Mode must be a string")
	if not _range(control, 0, 9007199254740991): return E.error("INVALID_INPUT", "Invalid control bits")
	version = int(version)
	control = int(control)
	var data = T.data_codeword_count(version, level)
	var out = {"version": version, "size": T.qr_size(version), "dataCodewords": data, "totalCodewords": T.raw_codeword_count(version), "capacityBits": data * 8, "errorCorrectionLevel": level, "mode": mode, "controlBits": control, "characterCountBits": -1, "modeIndicatorBits": -1, "payloadBits": -1, "maximum": -1, "maxCharacters": null, "maxBytes": null}
	if mode != "":
		var width = T.character_count_bits(version, mode)
		if E.is_error(width): return width
		var available = maxi(0, data * 8 - control - 4 - width)
		var maximum
		if mode == "numeric": maximum = int(available / 10) * 3 + (2 if available % 10 >= 7 else (1 if available % 10 >= 4 else 0))
		elif mode == "alphanumeric": maximum = int(available / 11) * 2 + (1 if available % 11 >= 6 else 0)
		elif mode == "byte": maximum = int(available / 8)
		else: maximum = int(available / 13)
		maximum = mini(maximum, (1 << width) - 1)
		out.characterCountBits = width
		out.modeIndicatorBits = 4
		out.payloadBits = available
		out.maximum = maximum
		out["maxBytes" if mode == "byte" else "maxCharacters"] = maximum
	return out

static func _segment_diagnostic(segment, version):
	return {"mode": segment.mode, "character_count": S.character_count(segment), "byte_count": S.byte_count(segment), "count": S.segment_count(segment), "bit_length": S.bit_length(segment, version)}

static func _warning(code, severity, message, details={}):
	return {"code": code, "severity": severity, "message": message, "details": details}

static func _diagnostics(segments, version, level, required, options, planning, ok):
	var capacity = 8 * T.data_codeword_count(version, level)
	var control = []
	var data = []
	var modes = []
	var input_bytes = 0
	var ec = -1
	var fn = ""
	var second = null
	var sa = null
	for segment in segments:
		var d = _segment_diagnostic(segment, version)
		data.append(d)
		input_bytes += S.logical_bytes(segment).size()
		if S.is_control(segment): control.append(d.duplicate(true))
		elif not segment.mode in modes: modes.append(segment.mode)
		if segment.mode == "eci" and ec < 0: ec = segment.assignmentNumber
		if segment.mode == "fnc1": fn = "first-position"
		if segment.mode == "fnc1-second":
			fn = "second-position"
			second = segment
		if segment.mode == "structured-append": sa = segment
	var mode = "byte" if modes.is_empty() else (modes[0] if modes.size() == 1 else "mixed")
	var warnings = []
	if options.margin < 4: warnings.append(_warning("QUIET_ZONE_TOO_SMALL", "warning", "QR readers expect at least four quiet-zone modules.", {"margin": options.margin}))
	var fg = R.parse_color(options.foreground, false)
	var bg = R.parse_color(options.background, false)
	var ratio = null
	if fg != null and bg != null:
		ratio = R.contrast_ratio(fg, bg)
		if ratio < 4.5: warnings.append(_warning("COLOR_CONTRAST_LOW", "warning", "Color contrast is below the recommended minimum.", {"ratio": ratio}))
		elif ratio < 7: warnings.append(_warning("COLOR_CONTRAST_MODERATE", "info", "Stronger color contrast is recommended.", {"ratio": ratio}))
		if fg[3] < 255 or bg[3] < 255: warnings.append(_warning("COLOR_ALPHA_USED", "warning", "Transparent colors can reduce scan reliability."))
	else: warnings.append(_warning("COLOR_CONTRAST_UNKNOWN", "info", "These SVG colors cannot be checked for contrast."))
	if capacity - required >= 0 and capacity - required < capacity * 0.05: warnings.append(_warning("CAPACITY_NEAR_LIMIT", "info", "The selected version is close to full capacity."))
	var mm = null
	var symbol_mm = null
	if options.printDpi != null:
		mm = float(options.scale) / options.printDpi * 25.4
		symbol_mm = (T.qr_size(version) + 2 * options.margin) * mm
		if mm < 0.25: warnings.append(_warning("PRINT_MODULE_TOO_SMALL", "warning", "Print modules are smaller than 0.25 mm.", {"module_size_mm": mm}))
	var blocking = []
	for warning in warnings:
		if warning.severity == "warning": blocking.append(warning.code)
	if not blocking.is_empty(): warnings.append(_warning("SCAN_RISK", "warning", "One or more settings may reduce scan reliability.", {"blocking_warnings": blocking}))
	var selection = "fixed" if options.version != 0 else ("auto-minimum" if ok else "auto-range")
	var reason = "Version %s was requested explicitly." % version if options.version != 0 else ("Version %s is the smallest version in %s..%s that fits." % [version, options.minVersion, options.maxVersion] if ok else "No version in %s..%s fits; capacity is for version %s." % [options.minVersion, options.maxVersion, version])
	var d = {"phase": "planning" if planning else "generation", "render_planned": false, "mask_evaluated": not planning, "codewords_built": not planning, "ok": ok, "capacity_version": version, "error_correction_level": level, "requested_error_correction_level": options.errorCorrectionLevel, "boosted_error_correction": level != options.errorCorrectionLevel, "version_selection": selection, "version_selection_reason": reason, "mode": mode, "control_segments": control, "segments": data, "data_bit_length": required, "capacity_bits": capacity, "remaining_bits": capacity - required, "overflow_bits": maxi(0, required - capacity), "capacity_utilization": float(required) / capacity, "input_bytes": input_bytes, "gs1": fn == "first-position", "gs1_validation": {"enabled": false, "element_count": 0, "ais": [], "has_separators": false}, "warnings": warnings, "version": version if ok or options.version != 0 else null, "size": T.qr_size(version) if ok or options.version != 0 else null, "eci_assignment_number": ec if ec >= 0 else null, "fnc1": fn if fn != "" else null, "fnc1_second": {"enabled": second != null, "application_indicator": second.applicationIndicator if second != null else null, "application_indicator_codeword": S.application_indicator_codeword(second) if second != null else null}, "structured_append": {"enabled": false, "index": null, "total": null, "parity": null, "sequence_index": null, "sequence_total": null, "sequence_indicator": null}}
	if sa != null: d.structured_append = {"enabled": true, "index": sa.index, "total": sa.total, "parity": sa.parity, "sequence_index": sa.index - 1, "sequence_total": sa.total - 1, "sequence_indicator": ((int(sa.index) - 1) << 4) | (int(sa.total) - 1)}
	d.quiet_zone = {"modules": options.margin, "recommended_modules": 4, "is_sufficient": options.margin >= 4}
	d.colors = {"ratio": ratio, "is_inspectable": ratio != null, "foreground_alpha": fg[3] if fg != null else null, "background_alpha": bg[3] if bg != null else null, "is_strong": ratio != null and ratio >= 7, "is_sufficient": ratio != null and ratio >= 4.5 and fg[3] == 255 and bg[3] == 255}
	d.print = {"dpi": options.printDpi, "module_pixels": options.scale, "module_size_mm": mm, "symbol_size_mm": symbol_mm, "recommended_minimum_module_size_mm": 0.25, "is_module_size_sufficient": mm >= 0.25 if mm != null else null}
	return d

static func _add_controls(data, options):
	if E.is_error(data): return data
	var out = []
	if options.eciAssignment >= 0: out.append(S.eci(options.eciAssignment))
	elif options.gs1 or options.fnc1: out.append(S.fnc1())
	elif options.fnc1Second != "": out.append(S.fnc1_second(options.fnc1Second))
	elif options.structuredAppend != null: out.append(options.structuredAppend)
	out.append_array(data)
	return S.normalize_segments(out)

static func _input_segments(value, version, options, optimize):
	var data = O.create_segments(value, options.mode, version, optimize, -1, options.allowKanji and options.eciAssignment < 0)
	if E.is_error(data): return data
	if options.gs1 or options.fnc1 or options.fnc1Second != "":
		var needs_escape = false
		for segment in data:
			if segment.mode == "alphanumeric" and "%" in segment.data: needs_escape = true
		if needs_escape:
			var escaped = []
			for segment in data:
				var next = S.new_segment("alphanumeric", segment.data.replace("%", "%%")) if segment.mode == "alphanumeric" else segment
				if E.is_error(next): return next
				escaped.append(next)
			if options.mode == "auto":
				var bytes = O.create_segments(value, "byte", version, false, -1, false)
				if E.is_error(bytes): return bytes
				var byte_bits = S.segments_bit_length(bytes, version)
				var escaped_bits = S.segments_bit_length(escaped, version)
				if E.is_error(byte_bits): return byte_bits
				if E.is_error(escaped_bits): return escaped_bits
				data = bytes if byte_bits < escaped_bits or (byte_bits == escaped_bits and bytes.size() < escaped.size()) else escaped
			else: data = escaped
	return _add_controls(data, options)

static func _select_plan(factory, options):
	var lo = options.minVersion if options.version == 0 else options.version
	var hi = options.maxVersion if options.version == 0 else options.version
	var cache = {}
	var required = {}
	var fits = {}
	var version = hi
	var data = []
	var req = 0
	var ok = false
	for candidate in range(lo, hi + 1):
		var group = 0 if candidate <= 9 else (1 if candidate <= 26 else 2)
		if not cache.has(group):
			cache[group] = factory.call(candidate)
			if E.is_error(cache[group]): return cache[group]
			required[group] = S.segments_bit_length(cache[group], candidate)
			if E.is_error(required[group]): return required[group]
			fits[group] = true
			for segment in cache[group]:
				if not S.is_control(segment) and S.segment_count(segment) >= (1 << T.character_count_bits(candidate, segment.mode)): fits[group] = false
		version = candidate
		data = cache[group]
		req = required[group]
		ok = fits[group] and req <= 8 * T.data_codeword_count(version, options.errorCorrectionLevel)
		if ok: break
	var level = options.errorCorrectionLevel
	if ok and options.boostErrorCorrection:
		for i in range(T.level_index(level), 4):
			if req <= 8 * T.data_codeword_count(version, LEVELS[i]): level = LEVELS[i]
	var capacity = 8 * T.data_codeword_count(version, level)
	return {"ok": ok, "version": version if ok or options.version != 0 else 0, "capacityVersion": version, "errorCorrectionLevel": level, "requestedErrorCorrectionLevel": options.errorCorrectionLevel, "boostedErrorCorrection": level != options.errorCorrectionLevel, "dataBitLength": req, "capacityBits": capacity, "remainingBits": capacity - req, "segments": data, "diagnostics": _diagnostics(data, version, level, req, options, true, ok)}

static func plan(value, raw=null):
	var options = normalize_options(raw)
	if E.is_error(options): return options
	var validation = null
	var optimize = options.optimizeSegments
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_BYTE_ARRAY:
		if options.gs1: return E.error("INVALID_GS1", "High-level GS1 requires text")
	else:
		var chars = S.strict_text(value)
		if E.is_error(chars): return chars
		if chars.size() > S.MAX_SINGLE_SYMBOL_CHARACTERS: optimize = false
		if options.gs1:
			var parsed = G.parse_gs1_element_string(value)
			if E.is_error(parsed): return parsed
			var ais = []
			for element in parsed.elements: ais.append(element.ai)
			validation = {"enabled": true, "element_count": parsed.elements.size(), "ais": ais, "has_separators": value.contains(String.chr(29))}
	var p = _select_plan(func(version): return _input_segments(value, version, options, optimize), options)
	if E.is_error(p): return p
	if validation != null: p.diagnostics.gs1_validation = validation
	return p

static func plan_segments(values, raw=null):
	var options = normalize_options(raw)
	if E.is_error(options): return options
	if options.gs1: return E.error("INVALID_GS1", "Manual GS1 requires an explicit FNC1 segment")
	var normalized = S.normalize_segments(values)
	if E.is_error(normalized): return normalized
	var found = _add_controls(normalized, options)
	if E.is_error(found): return found
	return _select_plan(func(_version): return found, options)

static func _build(p, options):
	if E.is_error(p): return p
	if not p.ok: return E.error("DATA_TOO_LONG", "Input does not fit the selected QR capacity")
	var version = p.capacityVersion
	var level = p.errorCorrectionLevel
	var bits = S.segments_bits(p.segments, version)
	if E.is_error(bits): return bits
	var data = C.pad_data_bits(bits, version, level)
	if E.is_error(data): return data
	var inter = C.interleave_codewords(data, version, level)
	if E.is_error(inter): return inter
	var built = C.build_matrix(inter.codewords, version, level, options.maskPattern)
	if E.is_error(built): return built
	var d = _diagnostics(p.segments, version, level, p.dataBitLength, options, false, true)
	d.gs1_validation = p.diagnostics.gs1_validation.duplicate(true)
	d.mask_pattern = built.maskPattern
	d.mask_penalty = built.penalty
	d.mask_penalties = []
	for row in built.maskPenalties: d.mask_penalties.append({"mask_pattern": row.maskPattern, "penalty": row.penalty})
	d.mask_selection_reason = "Lowest penalty; first mask wins ties." if options.maskPattern < 0 else "Explicit mask requested."
	d.data_codewords = data.size()
	d.error_correction_codewords = inter.codewords.size() - data.size()
	d.total_codewords = inter.codewords.size()
	return {"matrix": built.matrix, "version": version, "maskPattern": built.maskPattern, "errorCorrectionLevel": level, "dataCodewords": data, "codewords": inter.codewords, "segments": p.segments, "diagnostics": d, "options": options}

static func generate(value, raw=null):
	var options = normalize_options(raw)
	if E.is_error(options): return options
	return _build(plan(value, options), options)

static func generate_segments(values, raw=null):
	var options = normalize_options(raw)
	if E.is_error(options): return options
	return _build(plan_segments(values, options), options)

static func estimate(value, raw=null):
	return plan(value, raw)

static func analyze_segments(values, raw=null):
	return plan_segments(values, raw)

static func diagnostics(value):
	if typeof(value) != TYPE_DICTIONARY or value.get("diagnostics") == null: return E.error("INVALID_INPUT", "Uninitialized diagnostics result")
	return E.copy_json_checked(value.diagnostics)

static func size(value):
	if typeof(value) != TYPE_DICTIONARY: return E.error("INVALID_INPUT", "QR result must be a dictionary")
	var valid = C.validate_matrix(value.get("matrix"))
	return valid if E.is_error(valid) else value.matrix.size()

static func module_at(value, x, y):
	var n = size(value)
	if E.is_error(n): return n
	if not _range(x, 0, n - 1) or not _range(y, 0, n - 1): return E.error("INVALID_INPUT", "Module coordinates are outside the matrix")
	return 1 if value.matrix[int(y)][int(x)] else 0
