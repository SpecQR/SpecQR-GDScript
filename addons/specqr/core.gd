extends RefCounted
## Scratch-built GF(256), Reed–Solomon, placement, masking and penalty scoring.
const E = preload("error.gd")
const T = preload("tables.gd")

static func validate_matrix(matrix):
	if typeof(matrix) != TYPE_ARRAY or matrix.size() < 1 or matrix.size() > 177:
		return E.error("INVALID_INPUT", "Matrix must be square, 1..177 modules")
	for row in matrix:
		if typeof(row) != TYPE_ARRAY or row.size() != matrix.size(): return E.error("INVALID_INPUT", "Matrix must be square")
		for value in row:
			if typeof(value) != TYPE_BOOL and not E.in_range(value, 0, 1): return E.error("INVALID_INPUT", "Matrix module must be boolean or 0/1")
	return null

static func copy_matrix(matrix):
	var valid = validate_matrix(matrix)
	if E.is_error(valid): return valid
	var result = []
	for row in matrix:
		var owned = []
		for value in row: owned.append(1 if value else 0)
		result.append(owned)
	return result

static func _blank(size):
	var result = []
	for _i in range(size):
		var row = []
		row.resize(size)
		row.fill(0)
		result.append(row)
	return result

static func _checked_bytes(data):
	if typeof(data) != TYPE_ARRAY and typeof(data) != TYPE_PACKED_BYTE_ARRAY: return E.error("INVALID_INPUT", "Codewords must be an Array or PackedByteArray")
	if data.size() > 3706: return E.error("INVALID_INPUT", "QR codeword count exceeds 3706")
	for value in data:
		if not E.in_range(value, 0, 255): return E.error("INVALID_INPUT", "Codeword must be an integer in 0..255")
	return null

static func pad_data_bits(bits, version, level):
	var capacity = T.data_codeword_count(version, level)
	if E.is_error(capacity): return capacity
	if typeof(bits) != TYPE_ARRAY: return E.error("INVALID_INPUT", "Bits must be an Array")
	if bits.size() > capacity * 8: return E.error("DATA_TOO_LONG", "Bits exceed data capacity")
	var result = []
	result.resize(capacity)
	result.fill(0)
	for i in range(bits.size()):
		if not E.in_range(bits[i], 0, 1): return E.error("INVALID_INPUT", "Bit must be an integer in 0..1")
		result[int(i / 8)] |= int(bits[i]) << (7 - i % 8)
	var terminated = bits.size() + mini(capacity * 8 - bits.size(), 4)
	var length = int((terminated + 7) / 8)
	for i in range(length, capacity): result[i] = 0xec if (i - length) % 2 == 0 else 0x11
	return result

static func _gf(left, right):
	var a = int(left)
	var b = int(right)
	var result = 0
	while b:
		if b & 1: result ^= a
		b >>= 1
		a <<= 1
		if a & 0x100: a ^= 0x11d
	return result

static func gf_multiply(left, right):
	if not E.in_range(left, 0, 255) or not E.in_range(right, 0, 255): return E.error("INVALID_INPUT", "GF operands must be integers in 0..255")
	return _gf(left, right)

static func reed_solomon_divisor(degree):
	if not E.in_range(degree, 1, 255): return E.error("INVALID_INPUT", "RS degree must be an integer in 1..255")
	var n = int(degree)
	var result = []
	result.resize(n + 1)
	result.fill(0)
	result[0] = 1
	var root = 1
	for factor in range(n):
		for i in range(factor + 1, 0, -1): result[i] ^= _gf(result[i - 1], root)
		root = _gf(root, 2)
	return result

static func _remainder(data, divisor):
	var degree = divisor.size() - 1
	var result = []
	result.resize(degree)
	result.fill(0)
	for value in data:
		var factor = int(value) ^ result[0]
		for i in range(degree - 1): result[i] = result[i + 1] ^ _gf(divisor[i + 1], factor)
		result[degree - 1] = _gf(divisor[degree], factor)
	return result

static func reed_solomon_remainder(data, degree):
	var valid = _checked_bytes(data)
	if E.is_error(valid): return valid
	var divisor = reed_solomon_divisor(degree)
	return divisor if E.is_error(divisor) else _remainder(data, divisor)

static func interleave_codewords(data, version, level):
	var info = T.block_info(version, level)
	if E.is_error(info): return info
	var valid = _checked_bytes(data)
	if E.is_error(valid): return valid
	if data.size() != info.dataCodewords: return E.error("INVALID_INPUT", "Wrong data codeword count")
	var short_count = info.blocks - info.rawCodewords % info.blocks
	var short_length = int(info.rawCodewords / info.blocks) - info.eccPerBlock
	var divisor = reed_solomon_divisor(info.eccPerBlock)
	var blocks = []
	var codewords = []
	var offset = 0
	for i in range(info.blocks):
		var n = short_length + (1 if i >= short_count else 0)
		var part = []
		for j in range(offset, offset + n): part.append(int(data[j]))
		blocks.append({"data": part, "ecc": _remainder(part, divisor)})
		offset += n
	for col in range(short_length + 1):
		for block in blocks:
			if col < block.data.size(): codewords.append(block.data[col])
	for col in range(info.eccPerBlock):
		for block in blocks: codewords.append(block.ecc[col])
	if offset != data.size() or codewords.size() != info.rawCodewords: return E.error("INVALID_INPUT", "Inconsistent interleaving")
	return {"codewords": codewords, "blocks": blocks, "dataCodewords": info.dataCodewords, "totalCodewords": info.rawCodewords, "errorCorrectionCodewords": info.rawCodewords - info.dataCodewords}

static func _mask(mask, x, y):
	match mask:
		0: return (x + y) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (x + y) % 3 == 0
		4: return (int(y / 2) + int(x / 3)) % 2 == 0
		5: return (x * y) % 2 + (x * y) % 3 == 0
		6: return ((x * y) % 2 + (x * y) % 3) % 2 == 0
	return ((x + y) % 2 + (x * y) % 3) % 2 == 0

static func mask_condition(mask, column, row):
	if not E.in_range(mask, 0, 7) or not E.in_range(column, 0, 176) or not E.in_range(row, 0, 176): return E.error("INVALID_INPUT", "Invalid mask or module coordinate")
	return _mask(int(mask), int(column), int(row))

static func _line_penalty(line):
	var color = -1
	var length = 0
	var window = 0
	var score = 0
	for i in range(line.size()):
		var value = 1 if line[i] else 0
		if value == color: length += 1
		else:
			if length >= 5: score += length - 2
			color = value
			length = 1
		window = ((window << 1) | value) & 0x7ff
		if i >= 10 and (window == 0b10111010000 or window == 0b00001011101): score += 40
	if length >= 5: score += length - 2
	return score

static func _penalty(matrix):
	var n = matrix.size()
	var score = 0
	var dark = 0
	for i in range(n):
		score += _line_penalty(matrix[i])
		var column = []
		for j in range(n):
			column.append(matrix[j][i])
			dark += 1 if matrix[j][i] else 0
		score += _line_penalty(column)
	for y in range(n - 1):
		for x in range(n - 1):
			var a = bool(matrix[y][x])
			if a == bool(matrix[y][x + 1]) and a == bool(matrix[y + 1][x]) and a == bool(matrix[y + 1][x + 1]): score += 3
	score += int(abs(dark * 20 - n * n * 10) / (n * n)) * 10
	return score

static func penalty_score(matrix):
	var valid = validate_matrix(matrix)
	return valid if E.is_error(valid) else _penalty(matrix)

static func _set_module(grid, x, y, dark):
	if x >= 0 and x < grid.side and y >= 0 and y < grid.side:
		grid.modules[y][x] = 1 if dark else 0
		grid.functions[y][x] = 1

static func _finder(grid, left, top):
	for dy in range(-1, 8):
		for dx in range(-1, 8):
			var inside = dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6
			_set_module(grid, left + dx, top + dy, inside and (dx == 0 or dx == 6 or dy == 0 or dy == 6 or (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4)))

static func _format(grid, level, mask):
	var data = (T.format_bits(level) << 3) | mask
	var remainder = data
	for _i in range(10): remainder = (remainder << 1) ^ (((remainder >> 9) & 1) * 0x537)
	var encoded = ((data << 10) | remainder) ^ 0x5412
	for i in range(6): _set_module(grid, 8, i, (encoded >> i) & 1)
	_set_module(grid, 8, 7, (encoded >> 6) & 1)
	_set_module(grid, 8, 8, (encoded >> 7) & 1)
	_set_module(grid, 7, 8, (encoded >> 8) & 1)
	for i in range(9, 15): _set_module(grid, 14 - i, 8, (encoded >> i) & 1)
	for i in range(8): _set_module(grid, grid.side - 1 - i, 8, (encoded >> i) & 1)
	for i in range(8, 15): _set_module(grid, 8, grid.side - 15 + i, (encoded >> i) & 1)

static func _functions(grid, version, level):
	_finder(grid, 0, 0)
	_finder(grid, grid.side - 7, 0)
	_finder(grid, 0, grid.side - 7)
	for i in range(8, grid.side - 8):
		_set_module(grid, i, 6, i % 2 == 0)
		_set_module(grid, 6, i, i % 2 == 0)
	var positions = T.alignment_positions(version)
	for yi in range(positions.size()):
		for xi in range(positions.size()):
			if (xi == 0 and yi == 0) or (xi == positions.size() - 1 and yi == 0) or (xi == 0 and yi == positions.size() - 1): continue
			for dy in range(-2, 3):
				for dx in range(-2, 3): _set_module(grid, positions[xi] + dx, positions[yi] + dy, maxi(abs(dx), abs(dy)) != 1)
	_format(grid, level, 0)
	_set_module(grid, 8, grid.side - 8, 1)
	if version >= 7:
		var remainder = version
		for _i in range(12): remainder = (remainder << 1) ^ (((remainder >> 11) & 1) * 0x1f25)
		var encoded = (version << 12) | remainder
		for i in range(18):
			var a = grid.side - 11 + i % 3
			var b = int(i / 3)
			_set_module(grid, a, b, (encoded >> i) & 1)
			_set_module(grid, b, a, (encoded >> i) & 1)

static func _draw_codewords(grid, words):
	var at = 0
	var right = grid.side - 1
	while right >= 1:
		if right == 6: right = 5
		for vertical in range(grid.side):
			var y = grid.side - 1 - vertical if ((right + 1) & 2) == 0 else vertical
			for x in [right, right - 1]:
				if not grid.functions[y][x]:
					if at < words.size() * 8: grid.modules[y][x] = (int(words[int(at / 8)]) >> (7 - at % 8)) & 1
					at += 1
		right -= 2
	if at - words.size() * 8 < 0 or at - words.size() * 8 > 7: return E.error("INVALID_INPUT", "Inconsistent data-module count")
	return null

static func build_matrix(words, version, level, mask = -1):
	var n = T.qr_size(version)
	if E.is_error(n): return n
	var valid = T.level_index(level)
	if E.is_error(valid): return valid
	if not E.in_range(mask, -1, 7): return E.error("INVALID_INPUT", "Mask must be an integer in -1..7")
	valid = _checked_bytes(words)
	if E.is_error(valid): return valid
	if words.size() != T.raw_codeword_count(version): return E.error("INVALID_INPUT", "Wrong interleaved codeword count")
	var base = {"side": n, "modules": _blank(n), "functions": _blank(n)}
	_functions(base, int(version), level)
	valid = _draw_codewords(base, words)
	if E.is_error(valid): return valid
	var output = {"penalty": 9000000000000000, "maskPenalties": []}
	for m in (range(8) if mask < 0 else [int(mask)]):
		var grid = {"side": n, "modules": base.modules.duplicate(true), "functions": base.functions}
		for y in range(n):
			for x in range(n):
				if not grid.functions[y][x] and _mask(m, x, y): grid.modules[y][x] ^= 1
		_format(grid, level, m)
		var score = _penalty(grid.modules)
		output.maskPenalties.append({"maskPattern": m, "penalty": score})
		if score < output.penalty:
			output.matrix = grid.modules
			output.maskPattern = m
			output.penalty = score
	return output
