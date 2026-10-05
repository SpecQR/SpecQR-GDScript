extends SceneTree
## Native JSONL test adapter. Request and response cardinality is exact.
const Protocol = preload("protocol.gd")
const StrictJSON = preload("strict_json.gd")
const LIMIT = 16 * 1024 * 1024
var buffer = PackedByteArray()
var discard = false

func respond():
	var parsed = StrictJSON.parse_bytes(buffer) if not discard else {"ok":false}
	var result = Protocol.run_request(parsed.value) if parsed.ok else Protocol.bad("JSON input resource limit" if discard else "Malformed JSON")
	print(StrictJSON.stringify(result))
	buffer.clear()
	discard=false

func accept_bytes(bytes):
	for byte in bytes:
		if byte==10: respond()
		elif not discard:
			if buffer.size()>=LIMIT:
				buffer.clear()
				discard=true
			else: buffer.append(byte)

func _initialize():
	var args=OS.get_cmdline_user_args()
	if args==PackedStringArray(["--runtime"]):
		var version=Engine.get_version_info()
		print(StrictJSON.stringify({"godot":version.string,"major":version.major,"minor":version.minor,"patch":version.patch,"status":version.status,"hash":version.hash,"os":OS.get_name(),"arch":Engine.get_architecture_name(),"nativeGDScript":true}))
		quit(0)
		return
	if not args.is_empty():
		printerr("Unexpected bridge arguments")
		quit(2)
		return
	if OS.has_method("read_buffer_from_stdin"):
		while true:
			# One-byte reads avoid a pipe deadlock when the caller waits for each
			# response. libc provides the underlying buffered input.
			var bytes=OS.call("read_buffer_from_stdin",1)
			if bytes.is_empty(): break
			accept_bytes(bytes)
	else:
		# Godot 4.3 uses fgets(1024): retain and join its raw line chunks.
		# Verification clients send ASCII JSON escapes, so chunk boundaries
		# cannot bisect UTF-8 scalars. Public library APIs accept native strings.
		while true:
			var chunk=OS.read_string_from_stdin()
			if chunk=="": break
			accept_bytes(chunk.to_utf8_buffer())
	if not buffer.is_empty() or discard: respond()
	quit(0)
