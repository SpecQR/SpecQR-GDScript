extends SceneTree
const O = preload("../addons/specqr/optimizer.gd")
const E = preload("../addons/specqr/error.gd")
var failures = []
var checked = 0
func check(condition, label):
	checked += 1
	if not condition: failures.append(label)
func make_tracker():
	var tracker = O.new_segment_optimization_tracker()
	for c in "ABCD123漢字12":
		var result = O.append_character(tracker, c)
		check(not E.is_error(result), "valid public append")
	return tracker
func reject_unchanged(tracker, label):
	var before = var_to_bytes(tracker)
	check(E.is_error(O.append_character(tracker, "A")), label + " rejected")
	check(var_to_bytes(tracker) == before, label + " unchanged")
func _initialize():
	var base = make_tracker()
	var t = O.new_segment_optimization_tracker()
	t.offsets = t.costs
	reject_unchanged(t, "initial offsets/costs alias")
	for pair in [["costs", "counts"], ["previous", "chosen"], ["offsets", "counts"]]:
		t = base.duplicate(true)
		t[pair[0]] = t[pair[1]]
		reject_unchanged(t, pair[0] + "/" + pair[1] + " alias")
	t = base.duplicate(true)
	t.keys[1] = t.keys[0]
	reject_unchanged(t, "mode keys alias")
	t = base.duplicate(true)
	t.queues[1] = t.queues[0]
	reject_unchanged(t, "mode queues alias")
	t = base.duplicate(true)
	t.queues[0][1] = t.queues[0][0]
	reject_unchanged(t, "queue dictionaries alias")
	t = base.duplicate(true)
	t.queues[0][1].values = t.queues[0][0].values
	reject_unchanged(t, "queue value arrays alias")
	for field in ["offsets", "costs", "counts", "previous", "chosen"]:
		for invalid in [null, true, "x", [], {}, Vector2.ONE, NAN, INF, -1, 9223372036854775807]:
			t = base.duplicate(true)
			t[field][2] = invalid
			reject_unchanged(t, "historical " + field + " type " + str(typeof(invalid)))
	for mode in range(4):
		t = base.duplicate(true)
		t.keys[mode][2] = null
		reject_unchanged(t, "historical key " + str(mode))
	for field in ["previous", "chosen"]:
		t = base.duplicate(true)
		t[field][1] = t
		var original_size = t.costs.size()
		check(E.is_error(O.append_character(t, "A")), field + " cycle rejected")
		check(t.costs.size() == original_size and is_same(t[field][1], t), field + " cycle unchanged")
		t[field][1] = 0
	t = base.duplicate(true)
	t.keys[0][1] = t.keys
	check(E.is_error(O.append_character(t, "A")), "key cycle rejected")
	check(is_same(t.keys[0][1], t.keys), "key cycle unchanged")
	t.keys[0][1] = 0
	t = base.duplicate(true)
	t.self = t
	check(E.is_error(O.append_character(t, "A")), "unknown cycle rejected")
	t.erase("self")
	t = base.duplicate(true)
	t.make_read_only()
	check(E.is_error(O.append_character(t, "A")), "read-only tracker rejected")
	t = base.duplicate(true)
	var old_costs = t.costs
	check(not E.is_error(O.append_character(t, "A")), "owned public append")
	check(not is_same(old_costs, t.costs), "historical container detached")
	old_costs[1] = -1
	check(not E.is_error(O.optimal_bits(t)), "historical alias cannot corrupt new state")
	t = base.duplicate(true)
	t.offsets.make_read_only()
	check(not E.is_error(O.append_character(t, "A")), "read-only history safely copied")
	var large = O.new_segment_optimization_tracker()
	for c in "abcé漢字1234567890".repeat(90): O._append_character_trusted(large, c)
	check(not E.is_error(O.optimal_bits(large)), "large private tracker validates")
	check(not E.is_error(O.append_character(large, "😀")), "large public append validates")
	print(JSON.stringify({"checked": checked, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
