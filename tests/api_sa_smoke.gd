extends SceneTree
const E = preload("../addons/specqr/error.gd")
const A = preload("../addons/specqr/api.gd")
const S = preload("../addons/specqr/segments.gd")
const O = preload("../addons/specqr/optimizer.gd")
const SA = preload("../addons/specqr/structured_append.gd")
var failures = []
var checked = 0
func check(condition, label):
	checked += 1
	if not condition: failures.append(label)
func _initialize():
	var o = A.normalize_options()
	check(not E.is_error(o) and o.version == 0 and o.errorCorrectionLevel == "M", "defaults")
	check(E.is_error(A.normalize_options({"version": true})), "boolean version rejected")
	check(E.is_error(A.normalize_options({"eci": true, "eciAssignment": 3})), "ECI alias mismatch")
	check(E.is_error(A.normalize_options({"gs1": true, "eci": 26})), "GS1/ECI conflict")
	check(A.get_capacity(1, "L", "byte").maximum == 17, "version 1 byte capacity")
	var p = A.plan("01234567")
	check(not E.is_error(p) and p.ok and p.dataBitLength == 41, "numeric plan")
	var q = A.generate("HELLO WORLD", {"errorCorrectionLevel": "L", "maskPattern": 0})
	check(not E.is_error(q) and q.version == 1 and q.matrix.size() == 21 and q.dataCodewords.size() == 19, "generate smoke")
	var escaped = A.plan("ABC%DEF", {"fnc1": true, "mode": "alphanumeric"})
	check(not E.is_error(escaped) and escaped.segments[1].data == "ABC%%DEF", "highlevel FNC1 percent escaped")
	var low = A.plan_segments([S.fnc1(), S.alphanumeric("ABC%DEF")])
	check(not E.is_error(low) and low.segments[1].data == "ABC%DEF", "manual FNC1 percent preserved")
	check(E.is_error(A.plan("ABC" + String.chr(29), {"fnc1": true, "mode": "alphanumeric"})), "forcedalpha GS rejected")
	var dense = A.plan("%%%%%%%%%%", {"fnc1": true})
	check(not E.is_error(dense) and dense.segments[1].mode == "byte", "percent-heavy byte comparison")
	var tracker = O.new_segment_optimization_tracker()
	for c in ["A", "1", "é"]:
		check(not E.is_error(O.append_character(tracker, c)), "tracker append " + c)
	check(O.optimal_bits(tracker) == 44, "tracker byte width")
	var input = "HELLO WORLD 1234567890 ".repeat(3)
	var set_result = SA.generate_structured_append(input, {"version": 1, "errorCorrectionLevel": "L"}, 16, true)
	check(not E.is_error(set_result) and set_result.total > 1, "SA generation")
	var parts = []
	if not E.is_error(set_result):
		for detail in set_result.diagnostics.symbols:
			parts.push_front({"index": detail.index, "total": detail.total, "parity": detail.parity, "data": input.substr(detail.input_start, detail.input_length)})
		var merged = SA.merge_structured_append_parts(parts)
		check(not E.is_error(merged) and merged.data == input, "SA reordered merge")
		parts[0].parity = (parts[0].parity + 1) % 256
		check(E.is_error(SA.merge_structured_append_parts(parts)), "SA parity mismatch")
	check(E.is_error(SA.generate_structured_append("A", {"version": 1})), "SA single symbol rejected")
	var bytes = [0, 1, 2, 255]
	var parity = SA.calculate_structured_append_parity(bytes)
	var merged_binary = SA.merge_structured_append_parts([{"index": 2, "total": 2, "parity": parity, "data": [2, 255]}, {"index": 1, "total": 2, "parity": parity, "data": [0, 1]}])
	check(not E.is_error(merged_binary) and merged_binary.data == bytes, "binary merge")
	check(A.normalize_options({"version": NAN}).code == "INVALID_VERSION", "NaN version code")
	check(A.normalize_options({"eciAssignment": INF}).code == "INVALID_ECI", "infinite ECI code")
	check(E.is_error(A.normalize_options({"scale": "1"})), "numeric string scale rejected")
	check(E.is_error(A.normalize_options({"optimizeSegments": 1})), "numeric boolean rejected")
	var packed = A.plan(PackedByteArray([0, 1, 255]))
	check(not E.is_error(packed) and packed.segments[0].binary, "PackedByteArray highlevel")
	var header = {"index": 1, "total": 2, "parity": 64}
	var owned_options = A.normalize_options({"structuredAppend": header})
	header.index = 2
	check(owned_options.structuredAppend.index == 1, "options header ownership")
	var source_bytes = [0, 1, 255]
	var owned_plan = A.plan(source_bytes)
	source_bytes[0] = 99
	check(owned_plan.segments[0].data[0] == 0, "plan payload ownership")
	var cyclic = []
	cyclic.append(cyclic)
	check(E.is_error(A.plan(cyclic)), "cyclic binary rejected")
	check(E.is_error(A.diagnostics({"diagnostics": cyclic})), "cyclic diagnostics rejected")
	cyclic.clear()
	var metadata_cases = [true, "2", 2.5, NAN, INF, -1, 17]
	for invalid in metadata_cases:
		check(E.is_error(SA.merge_structured_append_parts([{"index": 1, "total": invalid, "parity": 0, "data": ""}])), "invalid merge metadata " + str(invalid))
	check(E.is_error(SA.merge_structured_append_parts([{"index": 1, "total": 2, "parity": 65, "data": "A"}, {"index": 2, "total": 2, "parity": 65, "data": []}])), "mixed merge types")
	for invalid_mode in [0, 1, true, false, {}, [], null, Vector2.ONE, NAN, INF]:
		var rejected = A.normalize_options({"structuredAppend": {"mode": invalid_mode, "index": 1, "total": 2, "parity": 0}})
		check(E.is_error(rejected) and rejected.code == "INVALID_MODE", "strict SA option mode " + str(typeof(invalid_mode)))
		check(E.is_error(SA.generate_segments_structured_append([{"mode": invalid_mode, "data": "A"}])), "strict manual SA mode " + str(typeof(invalid_mode)))
	print(JSON.stringify({"checked": checked, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
