extends RefCounted
## Bounded RFC 8259 parser. Reject duplicate keys, nonfinite numbers, invalid
## UTF-8 and unpaired UTF-16 escapes before any engine decoder can log warnings.
var text = ""
var pos = 0
var valid = true
var nodes = 0

static func parse_bytes(bytes):
	var i = 0
	while i < bytes.size():
		var first = bytes[i]
		if first==0: return {"ok":false}
		var count = 1
		var cp = first
		if first >= 0x80:
			if first >= 0xc2 and first <= 0xdf: count=2; cp=first&31
			elif first >= 0xe0 and first <= 0xef: count=3; cp=first&15
			elif first >= 0xf0 and first <= 0xf4: count=4; cp=first&7
			else: return {"ok":false}
			if i + count > bytes.size(): return {"ok":false}
			for j in range(1,count):
				if bytes[i+j] < 0x80 or bytes[i+j] > 0xbf: return {"ok":false}
				cp=(cp<<6)|(bytes[i+j]&63)
			if cp < (0x80 if count==2 else 0x800 if count==3 else 0x10000) or cp > 0x10ffff or (cp>=0xd800 and cp<=0xdfff): return {"ok":false}
		i += count
	var parser = load("res://script/strict_json.gd").new()
	parser.text = bytes.get_string_from_utf8()
	var value = parser._value(0)
	parser._space()
	return {"ok":parser.valid and parser.pos == parser.text.length(),"value":value}

func _space():
	while pos < text.length() and text[pos] in [" ","\t","\r","\n"]: pos+=1

func _hex4():
	if pos+4>text.length(): valid=false; return 0
	var token=text.substr(pos,4)
	pos+=4
	for ch in token:
		if ch not in "0123456789abcdefABCDEF": valid=false; return 0
	return token.hex_to_int()

func _string():
	pos+=1
	var out=""
	while pos<text.length() and valid:
		var ch=text[pos]
		pos+=1
		if ch=='"': return out
		if ch=='\\':
			if pos>=text.length(): valid=false; return ""
			ch=text[pos]; pos+=1
			if ch=='u':
				var cp=_hex4()
				if cp==0: valid=false; return ""
				if cp>=0xd800 and cp<=0xdbff:
					if text.substr(pos,2)!='\\u': valid=false; return ""
					pos+=2
					var low=_hex4()
					if low<0xdc00 or low>0xdfff: valid=false; return ""
					cp=0x10000+((cp-0xd800)<<10)+(low-0xdc00)
				elif cp>=0xdc00 and cp<=0xdfff: valid=false; return ""
				if valid: out+=String.chr(cp)
			elif ch in ['"','\\','/']: out+=ch
			elif ch=='b': out+='\b'
			elif ch=='f': out+=String.chr(12)
			elif ch=='n': out+='\n'
			elif ch=='r': out+='\r'
			elif ch=='t': out+='\t'
			else: valid=false
		elif ch.unicode_at(0)<32: valid=false
		else: out+=ch
	valid=false
	return ""

func _number():
	var start=pos
	if text[pos]=='-': pos+=1
	if pos>=text.length(): valid=false; return null
	if text[pos]=='0': pos+=1
	elif text[pos] in '123456789':
		while pos<text.length() and text[pos] in '0123456789': pos+=1
	else: valid=false; return null
	if pos<text.length() and text[pos]=='.':
		pos+=1
		var begin=pos
		while pos<text.length() and text[pos] in '0123456789': pos+=1
		if pos==begin: valid=false; return null
	if pos<text.length() and text[pos] in ['e','E']:
		pos+=1
		if pos<text.length() and text[pos] in ['+','-']: pos+=1
		var begin=pos
		while pos<text.length() and text[pos] in '0123456789': pos+=1
		if pos==begin: valid=false; return null
	var token=text.substr(start,pos-start)
	if token.length()>512: valid=false; return null
	var whole_token=token.trim_prefix('-').split('.')[0].split('e')[0].split('E')[0].lstrip('0')
	if whole_token.length()>309: valid=false; return null
	var exponent_at=token.to_lower().find('e')
	if exponent_at>=0:
		var exponent_text=token.substr(exponent_at+1).trim_prefix('+').trim_prefix('-').lstrip('0')
		if exponent_text.length()>3: valid=false; return null
		var exponent=token.substr(exponent_at+1).to_int()
		var mantissa=token.substr(0,exponent_at).trim_prefix('-')
		var decimal=mantissa.find('.')
		var whole=mantissa if decimal<0 else mantissa.substr(0,decimal)
		var effective=exponent+maxi(0,whole.lstrip('0').length()-1)
		if effective>308 or exponent< -308: valid=false; return null
	var value=token.to_float()
	if not is_finite(value): valid=false; return null
	# All QR parameters are far below 2^53. Preserve exact signed 64-bit tokens
	# for hostile boundary inputs without converting them through floating point.
	if token.is_valid_int() and token.length()<19: return token.to_int()
	if token.is_valid_int() and (token=='-9223372036854775808' or token=='9223372036854775807'): return token.to_int()
	return value

func _value(depth):
	nodes+=1
	if depth>64 or nodes>1000000: valid=false; return null
	_space()
	if pos>=text.length(): valid=false; return null
	var ch=text[pos]
	if ch=='"': return _string()
	if ch=='{' or ch=='[':
		pos+=1
		var object=ch=='{'
		var out={} if object else []
		var close='}' if object else ']'
		_space()
		if pos<text.length() and text[pos]==close: pos+=1; return out
		while valid:
			_space()
			var key=null
			if object:
				if pos>=text.length() or text[pos]!='"': valid=false; return null
				key=_string()
				if not valid or out.has(key): valid=false; return null
				_space()
				if pos>=text.length() or text[pos]!=':': valid=false; return null
				pos+=1
			var value=_value(depth+1)
			if not valid: return null
			if object: out[key]=value
			else: out.append(value)
			_space()
			if pos>=text.length(): valid=false; return null
			if text[pos]==close: pos+=1; return out
			if text[pos]!=',': valid=false; return null
			pos+=1
		return null
	for token in ['true','false','null']:
		if text.substr(pos,token.length())==token:
			pos+=token.length()
			return true if token=='true' else false if token=='false' else null
	if ch=='-' or ch in '0123456789': return _number()
	valid=false
	return null

static func stringify(value):
	var encoded=JSON.stringify(value)
	# Godot 4.3's JSON writer leaves several ASCII controls literal, including
	# GS1's U+001D. Escape every such byte before emitting RFC 8259 JSONL.
	for cp in range(1,32): encoded=encoded.replace(String.chr(cp),'\\u%04x' % cp)
	return encoded
