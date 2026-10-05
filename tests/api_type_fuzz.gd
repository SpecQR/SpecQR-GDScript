extends SceneTree
const A = preload("../addons/specqr/api.gd")
const O = preload("../addons/specqr/optimizer.gd")
const SA = preload("../addons/specqr/structured_append.gd")
const E = preload("../addons/specqr/error.gd")
var checked = 0
var failures = []
func check_result(result, label, success_type=TYPE_DICTIONARY):
	checked += 1
	if not E.is_error(result) and typeof(result) != success_type: failures.append(label)
func _initialize():
	var variants = [null, false, true, 0, 1, -1, INF, NAN, "", "x", [], {}, PackedByteArray([1]), Vector2.ONE, RefCounted.new()]
	var options = ["errorCorrectionLevel", "errorCorrection", "version", "minVersion", "maxVersion", "maskPattern", "mode", "optimizeSegments", "allowKanji", "boostErrorCorrection", "eciAssignment", "eci", "gs1", "fnc1", "fnc1Second", "structuredAppend", "margin", "scale", "foreground", "background", "printDpi", "encoding", "output", "diagnostics"]
	for option in options:
		for value in variants:
			check_result(A.normalize_options({option: value}), "normalize " + option + " " + str(typeof(value)))
	for value in variants:
		check_result(A.get_capacity(value), "capacity version")
		check_result(A.get_capacity(1, value), "capacity level")
		check_result(A.get_capacity(1, "M", value), "capacity mode")
		check_result(A.get_capacity(1, "M", "byte", value), "capacity control bits")
		check_result(A.plan(value), "plan input")
		check_result(A.plan_segments(value), "plan manual input")
		check_result(SA.generate_structured_append(value, {"version": 1}), "SA input")
		check_result(SA.generate_segments_structured_append(value, {"version": 1}), "SA manual input")
		check_result(SA.merge_structured_append_parts(value), "SA merge input")
		check_result(O.create_segments(value), "optimizer input", TYPE_ARRAY)
		check_result(O.create_segments("A", value), "optimizer mode", TYPE_ARRAY)
		check_result(O.create_segments("A", "auto", value), "optimizer version", TYPE_ARRAY)
		check_result(O.create_segments("A", "auto", 1, value), "optimizer boolean", TYPE_ARRAY)
		for field in ["mode", "index", "total", "parity"]:
			var header = {"mode": "structured-append", "index": 1, "total": 2, "parity": 0}
			header[field] = value
			check_result(A.normalize_options({"structuredAppend": header}), "SA header " + field)
	print(JSON.stringify({"checked": checked, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
