extends RefCounted
## Checked result helpers. Expected invalid input is returned, never asserted.

static func error(code, message):
	return {"error": "SpecQRError", "isSpecQRError": true, "code": code, "message": message}

static func is_error(value):
	return typeof(value) == TYPE_DICTIONARY and typeof(value.get("isSpecQRError")) == TYPE_BOOL and value.get("isSpecQRError") == true and typeof(value.get("code")) == TYPE_STRING

static func is_number(value):
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))

static func is_integer(value):
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func in_range(value, low, high):
	return is_integer(value) and value >= low and value <= high

static func string_valid(value):
	if typeof(value) != TYPE_STRING:
		return false
	for i in range(value.length()):
		var cp = value.unicode_at(i)
		if cp < 0 or cp > 0x10ffff or (cp >= 0xd800 and cp <= 0xdfff):
			return false
	return true

static func require_integer(value, label = "Value", code = "INVALID_INPUT"):
	return value if is_integer(value) else error(code, label + " must be an integer")

static func require_range(value, low, high, label = "Value", code = "INVALID_INPUT"):
	return int(value) if in_range(value, low, high) else error(code, label + " is outside its supported integer range")

static func require_number(value, label = "Value", code = "INVALID_INPUT"):
	return value if is_number(value) else error(code, label + " must be a finite number")

static func require_string(value, label = "Value", code = "INVALID_INPUT"):
	return value if string_valid(value) else error(code, label + " must be a Unicode scalar string")

static func require_bool(value, label = "Value", code = "INVALID_INPUT"):
	return value if typeof(value) == TYPE_BOOL else error(code, label + " must be a boolean")

static func require_array(value, label = "Value", code = "INVALID_INPUT"):
	return value if typeof(value) == TYPE_ARRAY else error(code, label + " must be an Array")

static func require_hash(value, label = "Value", code = "INVALID_INPUT"):
	return value if typeof(value) == TYPE_DICTIONARY else error(code, label + " must be a Dictionary")

static func copy_json_checked(value):
	var state = [0, null]
	var owned = _copy(value, [], state, 0)
	return state[1] if state[1] != null else owned

static func _copy_error(state, message):
	state[1] = error("INVALID_INPUT", message)
	return null

static func _copy(value, active, visited, depth):
	visited[0] += 1
	if depth > 64 or visited[0] > 1000000:
		return _copy_error(visited, "Diagnostics exceed tree budget")
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			return value if is_finite(value) else _copy_error(visited, "Diagnostics contain a non-finite number")
		TYPE_STRING:
			if value.length() > 4000000 or not string_valid(value):
				return _copy_error(visited, "Diagnostics contain an invalid or oversized string")
			return value
		TYPE_ARRAY, TYPE_DICTIONARY:
			for previous in active:
				if is_same(value, previous):
					return _copy_error(visited, "Diagnostics must not contain cycles")
			if value.size() > 1000000 - visited[0]:
				return _copy_error(visited, "Diagnostics exceed tree budget")
			active.append(value)
			if typeof(value) == TYPE_ARRAY:
				var result = []
				for item in value:
					var owned = _copy(item, active, visited, depth + 1)
					if visited[1] != null:
						active.pop_back()
						return owned
					result.append(owned)
				active.pop_back()
				return result
			var result = {}
			for key in value:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					active.pop_back()
					return _copy_error(visited, "Diagnostics keys must be String or StringName")
				if key.length() > 4000000:
					active.pop_back()
					return _copy_error(visited, "Diagnostics key exceeds budget")
				var name = String(key)
				if not string_valid(name) or result.has(name):
					active.pop_back()
					return _copy_error(visited, "Diagnostics keys must be unique Unicode scalar strings")
				var owned = _copy(value[key], active, visited, depth + 1)
				if visited[1] != null:
					active.pop_back()
					return owned
				result[name] = owned
			active.pop_back()
			return result
	return _copy_error(visited, "Diagnostics must be a JSON-compatible tree")
