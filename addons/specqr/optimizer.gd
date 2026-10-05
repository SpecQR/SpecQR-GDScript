extends RefCounted

const E = preload("error.gd")
const T = preload("tables.gd")
const S = preload("segments.gd")
const MODES = ["numeric", "alphanumeric", "kanji", "byte"]

static func _range(value, lo, hi):
	return E.is_integer(value) and value >= lo and value <= hi

static func new_segment_optimization_tracker(version=1, allow_kanji=true):
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	if typeof(allow_kanji) != TYPE_BOOL: return E.error("INVALID_INPUT", "allowKanji must be a boolean")
	var queues = []
	var keys = []
	var widths = []
	for mode in MODES:
		queues.append([{"values": [], "head": 0}, {"values": [], "head": 0}, {"values": [], "head": 0}])
		keys.append([])
		widths.append(T.character_count_bits(version, mode))
	return {"version": int(version), "allowKanji": allow_kanji, "offsets": [0], "costs": [0], "counts": [0], "previous": [0], "chosen": [0], "queues": queues, "keys": keys, "widths": widths}

static func _base(t, mode, at):
	if mode == 0: return 10 * int(at / 3)
	if mode == 1: return 11 * int(at / 2)
	if mode == 2: return 13 * at
	return 8 * t.offsets[at]

static func _eligible(c, mode, allow):
	if mode == 0: return c >= "0" and c <= "9"
	if mode == 1: return S.alpha_value(c) >= 0
	if mode == 2: return allow and S.can_encode_kanji(c)
	return true

static func _payload(t, mode, a, b):
	var n = b - a
	if mode == 0: return 10 * int(n / 3) + [0, 4, 7][n % 3]
	if mode == 1: return 11 * int(n / 2) + 6 * (n % 2)
	if mode == 2: return 13 * n
	return 8 * (t.offsets[b] - t.offsets[a])

static func _count(t, mode, a, b):
	return t.offsets[b] - t.offsets[a] if mode == 3 else b - a

# Trackers are public dictionaries. Every container and historical primitive must
# be checked before a public operation may mutate anything. Private optimizers
# create their own tracker and use the trusted append path below instead.
static func _take_container(value, containers):
	for previous in containers:
		if is_same(value, previous): return false
	containers.append(value)
	return true

static func _validate_tracker(t):
	if typeof(t) != TYPE_DICTIONARY: return E.error("INVALID_INPUT", "Optimizer tracker must be a dictionary")
	var allowed = ["version", "allowKanji", "offsets", "costs", "counts", "previous", "chosen", "queues", "keys", "widths"]
	if t.size() != allowed.size(): return E.error("INVALID_INPUT", "Invalid tracker fields")
	for key in t:
		if typeof(key) != TYPE_STRING or not key in allowed: return E.error("INVALID_INPUT", "Invalid tracker fields")
	var valid = T.validate_version(t.get("version"))
	if E.is_error(valid): return valid
	if typeof(t.get("allowKanji")) != TYPE_BOOL: return E.error("INVALID_INPUT", "Tracker allowKanji must be a boolean")
	if typeof(t.get("costs")) != TYPE_ARRAY: return E.error("INVALID_INPUT", "Tracker costs must be an array")
	var n = t.costs.size()
	if n == 0 or n > S.MAX_PAYLOAD_UNITS + 1: return E.error("INVALID_INPUT", "Uninitialized or oversized tracker")
	var containers = [t]
	for key in ["costs", "offsets", "counts", "previous", "chosen"]:
		if typeof(t.get(key)) != TYPE_ARRAY or t[key].size() != n: return E.error("INVALID_INPUT", "Inconsistent tracker lengths")
		if not _take_container(t[key], containers): return E.error("INVALID_INPUT", "Tracker containers must not alias")
	for key in ["widths", "keys", "queues"]:
		if typeof(t.get(key)) != TYPE_ARRAY or t[key].size() != 4: return E.error("INVALID_INPUT", "Inconsistent tracker mode arrays")
		if not _take_container(t[key], containers): return E.error("INVALID_INPUT", "Tracker containers must not alias")
	for mode in range(4):
		if not _range(t.widths[mode], 1, 16) or t.widths[mode] != T.character_count_bits(t.version, MODES[mode]): return E.error("INVALID_INPUT", "Inconsistent tracker count width")
		if typeof(t.keys[mode]) != TYPE_ARRAY or t.keys[mode].size() != n - 1: return E.error("INVALID_INPUT", "Inconsistent tracker key lengths")
		if typeof(t.queues[mode]) != TYPE_ARRAY or t.queues[mode].size() != 3: return E.error("INVALID_INPUT", "Inconsistent tracker lanes")
		if not _take_container(t.keys[mode], containers) or not _take_container(t.queues[mode], containers): return E.error("INVALID_INPUT", "Tracker containers must not alias")
		for q in t.queues[mode]:
			if typeof(q) != TYPE_DICTIONARY or q.size() != 2 or not q.has("values") or not q.has("head") or typeof(q.get("values")) != TYPE_ARRAY: return E.error("INVALID_INPUT", "Invalid tracker queue")
			if not _take_container(q, containers) or not _take_container(q.values, containers): return E.error("INVALID_INPUT", "Tracker containers must not alias")
			if q.values.size() > n - 1 or not _range(q.head, 0, q.values.size()): return E.error("INVALID_INPUT", "Invalid tracker queue head or size")
	for i in range(n):
		if not _range(t.costs[i], 0, 100000000) or not _range(t.counts[i], 0, S.MAX_PAYLOAD_UNITS) or not _range(t.offsets[i], 0, 4 * S.MAX_PAYLOAD_UNITS): return E.error("INVALID_INPUT", "Invalid tracker history value")
		if not _range(t.previous[i], 0, maxi(0, i - 1)) or not _range(t.chosen[i], 0, 3): return E.error("INVALID_INPUT", "Invalid tracker predecessor or mode")
		if i == 0:
			if t.costs[i] != 0 or t.counts[i] != 0 or t.offsets[i] != 0 or t.previous[i] != 0 or t.chosen[i] != 0: return E.error("INVALID_INPUT", "Invalid tracker initial state")
		else:
			if t.offsets[i] - t.offsets[i - 1] < 1 or t.offsets[i] - t.offsets[i - 1] > 4: return E.error("INVALID_INPUT", "Invalid tracker scalar width")
			var previous = int(t.previous[i])
			var mode = int(t.chosen[i])
			if mode == 2 and not t.allowKanji: return E.error("INVALID_INPUT", "Invalid tracker Kanji path")
			if mode < 2 and t.offsets[i] - t.offsets[previous] != i - previous: return E.error("INVALID_INPUT", "Invalid tracker ASCII path")
			if _count(t, mode, previous, i) >= (1 << int(t.widths[mode])): return E.error("INVALID_INPUT", "Invalid tracker path count")
			if t.counts[i] != t.counts[previous] + 1 or t.costs[i] != t.costs[previous] + 4 + t.widths[mode] + _payload(t, mode, previous, i): return E.error("INVALID_INPUT", "Inconsistent tracker path")
	for mode in range(4):
		for i in range(n - 1):
			if not E.is_integer(t.keys[mode][i]) or t.keys[mode][i] != t.costs[i] - _base(t, mode, i): return E.error("INVALID_INPUT", "Invalid tracker key history")
		var lanes = 3 if mode == 0 else (2 if mode == 1 else 1)
		for lane in range(3):
			var q = t.queues[mode][lane]
			if lane >= lanes and (not q.values.is_empty() or q.head != 0): return E.error("INVALID_INPUT", "Invalid unused tracker lane")
			var last = -1
			for i in range(q.values.size()):
				var value = q.values[i]
				if not _range(value, 0, n - 2) or value <= last or int(value) % lanes != lane: return E.error("INVALID_INPUT", "Invalid tracker queue index")
				value = int(value)
				if i < q.head and _count(t, mode, value, n - 1) < (1 << int(t.widths[mode])): return E.error("INVALID_INPUT", "Invalid tracker queue cursor")
				if i >= q.head:
					if _count(t, mode, value, n - 1) >= (1 << int(t.widths[mode])): return E.error("INVALID_INPUT", "Expired tracker queue entry")
					if i > q.head and (t.keys[mode][last] > t.keys[mode][value] or (t.keys[mode][last] == t.keys[mode][value] and t.counts[last] > t.counts[value])): return E.error("INVALID_INPUT", "Inconsistent tracker queue order")
				last = value
	return null

static func append_character(t, c):
	var valid = _validate_tracker(t)
	if E.is_error(valid): return valid
	if t.is_read_only(): return E.error("INVALID_INPUT", "Optimizer tracker must be writable")
	var chars = S.strict_text(c)
	if E.is_error(chars): return chars
	if chars.size() != 1: return E.error("INVALID_INPUT", "Expected one Unicode scalar")
	if t.costs.size() > S.MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Optimizer resource limit exceeded")
	# Commit only a successfully updated owned state. This also prevents a caller's
	# retained references to historical arrays from mutating the new tracker.
	var owned = t.duplicate(true)
	var result = _append_character_trusted(owned, c)
	if E.is_error(result): return result
	t.clear()
	t.merge(owned)
	return result

# Internal only: t and c come from validated input and a fresh private tracker.
static func _append_character_trusted(t, c):
	var n = t.costs.size()
	if n > S.MAX_PAYLOAD_UNITS: return E.error("DATA_TOO_LONG", "Optimizer resource limit exceeded")
	var cp = c.unicode_at(0)
	var width = 1 if cp < 128 else (2 if cp < 2048 else (3 if cp < 65536 else 4))
	t.offsets.append(t.offsets[-1] + width)
	var best_cost = 9000000000000000
	var best_count = 9000000000000000
	var best_mode = -1
	var best_start = 0
	for mode in range(4):
		var start = n - 1
		var key = t.costs[start] - _base(t, mode, start)
		t.keys[mode].append(key)
		if not _eligible(c, mode, t.allowKanji):
			t.queues[mode] = [{"values": [], "head": 0}, {"values": [], "head": 0}, {"values": [], "head": 0}]
			continue
		var lanes = 3 if mode == 0 else (2 if mode == 1 else 1)
		var q = t.queues[mode][start % lanes]
		while q.values.size() > q.head:
			var j = q.values[-1]
			if not _range(j, 0, start) or not E.is_number(t.keys[mode][int(j)]) or not _range(t.counts[int(j)], 0, S.MAX_PAYLOAD_UNITS): return E.error("INVALID_INPUT", "Invalid tracker queue value")
			if not (t.keys[mode][int(j)] > key or (t.keys[mode][int(j)] == key and t.counts[int(j)] > t.counts[start])): break
			q.values.pop_back()
		q.values.append(start)
		var limit = (1 << int(t.widths[mode])) - 1
		for lane in range(lanes):
			var queue = t.queues[mode][lane]
			while queue.head < queue.values.size():
				var index = queue.values[int(queue.head)]
				if not _range(index, 0, start) or not _range(t.offsets[int(index)], 0, 4 * S.MAX_PAYLOAD_UNITS): return E.error("INVALID_INPUT", "Invalid tracker queue index")
				if _count(t, mode, int(index), n) <= limit: break
				queue.head += 1
			if queue.head >= queue.values.size(): continue
			var j = int(queue.values[int(queue.head)])
			if not _range(t.costs[j], 0, 100000000) or not _range(t.counts[j], 0, S.MAX_PAYLOAD_UNITS): return E.error("INVALID_INPUT", "Invalid tracker cost")
			var cost = t.costs[j] + 4 + t.widths[mode] + _payload(t, mode, j, n)
			var count = t.counts[j] + 1
			if cost < best_cost or (cost == best_cost and count < best_count):
				best_cost = cost
				best_count = count
				best_mode = mode
				best_start = j
	if best_mode < 0: return E.error("INVALID_INPUT", "No segmentation path")
	t.costs.append(best_cost)
	t.counts.append(best_count)
	t.chosen.append(best_mode)
	t.previous.append(best_start)
	return best_cost

static func optimal_bits(t):
	var valid = _validate_tracker(t)
	return valid if E.is_error(valid) else t.costs[-1]

static func optimize_segments(text, version=1, allow_kanji=true):
	var chars = S.strict_text(text)
	if E.is_error(chars): return chars
	if chars.size() > S.MAX_SINGLE_SYMBOL_CHARACTERS: return E.error("DATA_TOO_LONG", "Optimized single-symbol input exceeds 7089 scalars")
	var tracker = new_segment_optimization_tracker(version, allow_kanji)
	if E.is_error(tracker): return tracker
	if chars.is_empty(): return [S.new_segment("byte", "")]
	for c in chars:
		var bits = _append_character_trusted(tracker, c)
		if E.is_error(bits): return bits
	var out = []
	var n = chars.size()
	while n > 0:
		var j = tracker.previous[n]
		var mode = tracker.chosen[n]
		var segment = S.new_segment(MODES[mode], text.substr(j, n - j))
		if E.is_error(segment): return segment
		out.append(segment)
		n = j
	out.reverse()
	return out

static func create_segments(input, mode="auto", version=1, optimize=true, eci_assignment=-1, allow_kanji=true):
	var valid = T.validate_version(version)
	if E.is_error(valid): return valid
	if typeof(mode) != TYPE_STRING or (mode != "auto" and not mode in MODES): return E.error("INVALID_MODE", "Unsupported data mode")
	if typeof(optimize) != TYPE_BOOL or typeof(allow_kanji) != TYPE_BOOL: return E.error("INVALID_INPUT", "Optimization settings must be booleans")
	if not _range(eci_assignment, -1, 999999): return E.error("INVALID_ECI", "Invalid ECI assignment")
	var out = []
	if eci_assignment >= 0: out.append(S.eci(eci_assignment))
	if typeof(input) == TYPE_ARRAY or typeof(input) == TYPE_PACKED_BYTE_ARRAY:
		if mode != "auto" and mode != "byte": return E.error("INVALID_MODE", "Binary input requires byte mode")
		var segment = S.byte_segment(input)
		if E.is_error(segment): return segment
		out.append(segment)
		return out
	var chars = S.strict_text(input)
	if E.is_error(chars): return chars
	var result
	if mode != "auto":
		result = S.new_segment(mode, input)
	elif optimize:
		result = optimize_segments(input, version, allow_kanji and eci_assignment < 0)
	else:
		var numeric = true
		var alpha = true
		var kanji = allow_kanji and eci_assignment < 0
		for c in chars:
			if c < "0" or c > "9": numeric = false
			if S.alpha_value(c) < 0: alpha = false
			if not S.can_encode_kanji(c): kanji = false
		var chosen = "numeric" if not chars.is_empty() and numeric else ("alphanumeric" if not chars.is_empty() and alpha else ("kanji" if not chars.is_empty() and kanji else "byte"))
		result = S.new_segment(chosen, input)
	if E.is_error(result): return result
	if typeof(result) == TYPE_ARRAY: out.append_array(result)
	else: out.append(result)
	return out
