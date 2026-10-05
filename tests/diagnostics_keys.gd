extends SceneTree
const A = preload("../addons/specqr/api.gd")
const SA = preload("../addons/specqr/structured_append.gd")
const E = preload("../addons/specqr/error.gd")
var failures = []
var checked = 0
func check(condition, label):
	checked += 1
	if not condition: failures.append(label)
func string_keys_only(value):
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if typeof(key) != TYPE_STRING or not string_keys_only(value[key]): return false
	elif typeof(value) == TYPE_ARRAY:
		for child in value:
			if not string_keys_only(child): return false
	return true
func snapshot(result, label):
	check(not E.is_error(result), label + " construction")
	if E.is_error(result): return null
	var copy = A.diagnostics(result)
	check(not E.is_error(copy), label + " snapshot succeeds")
	if E.is_error(copy): return null
	check(copy == result.diagnostics, label + " snapshot content")
	check(string_keys_only(copy), label + " all nested keys are Strings")
	copy["snapshot_marker"] = true
	check(not result.diagnostics.has("snapshot_marker"), label + " root ownership")
	return copy
func _initialize():
	var string_options = {"version": 1, "errorCorrectionLevel": "M", "maskPattern": 0, "optimizeSegments": true}
	var name_options = {&"version": 1, &"errorCorrectionLevel": "M", &"maskPattern": 0, &"optimizeSegments": true}
	var dot_options = {}
	dot_options.version = 1
	dot_options.errorCorrectionLevel = "M"
	dot_options.maskPattern = 0
	dot_options.optimizeSegments = true
	var expected = A.normalize_options(string_options)
	var expected_q = A.generate("A", string_options)
	for raw in [string_options, name_options, dot_options]:
		var normalized = A.normalize_options(raw)
		check(not E.is_error(normalized) and normalized == expected, "equivalent normalized option key types")
		check(string_keys_only(normalized), "normalized options have String keys")
		var generated = A.generate("A", raw)
		check(not E.is_error(generated) and generated.matrix == expected_q.matrix, "equivalent generated option key types")
	var string_capacity = {"version": 1, "errorCorrectionLevel": "L", "mode": "byte", "controlBits": 4}
	var name_capacity = {&"version": 1, &"errorCorrectionLevel": "L", &"mode": "byte", &"controlBits": 4}
	var dot_capacity = {}
	dot_capacity.version = 1
	dot_capacity.errorCorrectionLevel = "L"
	dot_capacity.mode = "byte"
	dot_capacity.controlBits = 4
	var capacity = A.get_capacity(string_capacity)
	for raw in [string_capacity, name_capacity, dot_capacity]:
		var result = A.get_capacity(raw)
		check(not E.is_error(result) and result == capacity, "equivalent capacity key types")
		check(string_keys_only(result), "capacity result String keys")
	var header = {}
	header.mode = "structured-append"
	header.index = 1
	header.total = 2
	header.parity = 0
	var owned = A.normalize_options({&"structuredAppend": header})
	check(not E.is_error(owned), "dot-keyed nested SA header")
	header.index = 2
	check(not E.is_error(owned) and owned.structuredAppend.index == 1, "normalized header copy ownership")
	check(E.is_error(A.normalize_options({&"mode": &"auto"})), "StringName mode value rejected")
	check(E.is_error(A.normalize_options({&"errorCorrectionLevel": &"M"})), "StringName ECC value rejected")
	check(E.is_error(A.normalize_options({&"optimizeSegments": 1})), "nonboolean option value rejected")
	check(E.is_error(A.get_capacity({&"version": 1, &"mode": &"byte"})), "StringName capacity mode value rejected")
	check(E.is_error(A.normalize_options({0: 1})), "integer option key rejected")
	check(E.is_error(A.get_capacity({0: 1})), "integer capacity key rejected")
	check(E.is_error(A.normalize_options({StringName("x".repeat(1024)): []})), "oversized unknown key rejected")
	var cyclic = {}
	cyclic.self = cyclic
	check(E.is_error(A.normalize_options({&"unknown": cyclic})), "unknown key rejected without copying cycle")
	cyclic.clear()
	var q = A.generate("A", {"maskPattern": 0})
	var q_copy = snapshot(q, "generated QR")
	if q_copy != null:
		q_copy.segments[0].mode = "changed"
		check(q.diagnostics.segments[0].mode == "alphanumeric", "generated nested ownership")
	var plan = A.plan("A")
	var plan_copy = snapshot(plan, "plan")
	if plan_copy != null:
		plan_copy.segments[0].count = 900
		check(plan.diagnostics.segments[0].count == 1, "plan nested ownership")
	var set_result = SA.generate_structured_append("ABCDEFGHIJKLMNOPQRSTUVWX".repeat(2), {&"version": 1, &"maskPattern": 0})
	var set_copy = snapshot(set_result, "SA set")
	if set_copy != null:
		set_copy.symbols[0].input_start = 900
		check(set_result.diagnostics.symbols[0].input_start == 0, "SA set nested ownership")
	var p1 = {}
	p1.index = 1
	p1.total = 2
	p1.parity = 3
	p1.data = "A"
	var p2 = {&"index": 2, &"total": 2, &"parity": 3, &"data": "B"}
	var merge = SA.merge_structured_append_parts([p1, p2])
	var merge_copy = snapshot(merge, "SA merge")
	if merge_copy != null:
		merge_copy.parity_check.actual = 900
		check(merge.diagnostics.parity_check.actual == 3, "SA merge nested ownership")
	check(E.is_error(A.diagnostics({"diagnostics": {"value": &"StringName value"}})), "diagnostic StringName values remain invalid")
	print(JSON.stringify({"checked": checked, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
