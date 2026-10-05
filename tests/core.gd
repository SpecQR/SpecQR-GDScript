extends RefCounted
const E=preload('../addons/specqr/error.gd')
const S=preload('../addons/specqr/segments.gd')
const C=preload('../addons/specqr/core.gd')
const A=preload('../addons/specqr/api.gd')
const T=preload('../addons/specqr/tables.gd')
const J=preload('../script/strict_json.gd')
const P=preload('../script/protocol.gd')
static func run(t):
 for bad in [true,false,null,1.5,'1',[],{},NAN,INF,-INF]:
  t.error(E.require_range(bad,0,255),'INVALID_INPUT','integer guard '+str(typeof(bad)))
 for bad in [null,true,1,[],{}]: t.error(S.numeric(bad),'INVALID_INPUT','text type guard')
 for bad in [-1,256,1.5,true,null,'0',{}]: t.error(S.byte_segment([bad]),'INVALID_INPUT','invalid byte')
 for bad in [-1,1000000,true,'26',null,NAN]: t.error(S.eci(bad),'INVALID_ECI','invalid ECI')
 for value in [0,127,128,16383,16384,999999]:
  var segment=S.eci(value)
  t.test(not E.is_error(segment),'ECI valid')
  t.test(S.bit_length(segment,1)==(12 if value<128 else 20 if value<16384 else 28),'ECI exact bit boundary')
 t.error(S.numeric('1a'),'INVALID_MODE','numeric mode rejects')
 t.error(S.alphanumeric('a'),'INVALID_MODE','alphanumeric rejects')
 t.error(S.kanji('🙂'),'INVALID_MODE','Kanji rejects')
 t.test(S.can_encode_kanji('漢') and S.can_encode_kanji('字'),'Kanji known')
 t.test(S.encode_utf8('漢字🙂')==[230,188,162,229,173,151,240,159,153,130],'Unicode UTF8 exact')
 var bytes=[0,29,127,128,255]
 var segment=S.byte_segment(bytes)
 bytes[0]=99
 t.test(S.logical_bytes(segment)==[0,29,127,128,255],'byte segment owns input and preserves zero')
 var output=S.logical_bytes(segment)
 output[0]=88
 t.test(S.logical_bytes(segment)[0]==0,'byte getter defensive copy')
 var packed=PackedByteArray([0,128,255])
 var psegment=S.byte_segment(packed)
 packed[0]=88
 t.test(S.logical_bytes(psegment)==[0,128,255],'PackedByteArray owned')
 var cycle=[]
 cycle.append(cycle)
 t.error(E.copy_json_checked(cycle),'INVALID_INPUT','Array cycle bounded')
 cycle.clear()
 var dictionary={}
 dictionary.self=dictionary
 t.error(E.copy_json_checked(dictionary),'INVALID_INPUT','Dictionary cycle bounded')
 dictionary.clear()
 var nested={'x':{'y':[1,2,3]}}
 var copy=E.copy_json_checked(nested)
 copy.x.y[0]=9
 t.test(nested.x.y[0]==1,'nested copy ownership')
 for bad in [NAN,INF,-INF,Vector2(1,2),Callable(),Object.new()]:
  t.error(E.copy_json_checked(bad),'INVALID_INPUT','non JSON native Variant')
  if typeof(bad)==TYPE_OBJECT: bad.free()
 for version in range(1,41):
  for ecc in ['L','M','Q','H']:
   var cap=A.get_capacity(version,ecc,'byte')
   t.test(not E.is_error(cap) and cap.dataCodewords*8==cap.capacityBits,'capacity bits')
   t.test(T.raw_codeword_count(version)>=cap.dataCodewords,'data within raw words')
 t.test(C.gf_multiply(0,255)==0 and C.gf_multiply(1,255)==255,'GF identities')
 for bad in [-1,256,true,'1']: t.error(C.gf_multiply(bad,1),'INVALID_INPUT','GF invalid type/range')
 for bad in [0,256,true,'7']: t.error(C.reed_solomon_divisor(bad),'INVALID_INPUT','RS invalid degree')
 for bad in [[],[[2]],[[0,0]],'matrix']:
  t.error(C.validate_matrix(bad),'INVALID_INPUT','matrix guard')
 for key in ['version','maskPattern','eciAssignment','margin','scale']:
  t.test(E.is_error(A.generate('A',{key:true})),'native bool not integer '+key)
 for key in ['optimizeSegments','allowKanji','boostErrorCorrection','gs1','fnc1']:
  t.error(A.generate('A',{key:1}),'INVALID_GS1' if key=='gs1' else 'INVALID_INPUT','native integer not boolean '+key)
 var q=A.generate([0,29,128,255],{'version':1,'errorCorrectionLevel':'M','maskPattern':0})
 t.test(not E.is_error(q),'native NUL binary generation')
 if not E.is_error(q):
  t.test(q.segments[0].binary and S.logical_bytes(q.segments[0])==[0,29,128,255],'NUL binary preserved through generation')
  var ds=A.diagnostics(q)
  t.test(typeof(ds)==TYPE_DICTIONARY and not E.is_error(ds) and ds==q.diagnostics,'generated diagnostics snapshot succeeds and preserves full value')
  if not E.is_error(ds):
   ds['test']=1
   ds.segments[0].mode='changed'
   t.test(not q.diagnostics.has('test') and q.diagnostics.segments[0].mode=='byte','diagnostics deep copy')
 for json in ['{"x":1,"x":2}','{"x":NaN}','{"x":1e999}','{"x":01}','{"x":1,}','[1,]','{"text":"\\ud800"}','{"text":"\\udc00"}','{"text":"a\\u0000b"}','true false','[','{"x":}']:
  t.test(not J.parse_bytes(json.to_utf8_buffer()).ok,'strict invalid JSON')
 for invalid in [PackedByteArray([0x80]),PackedByteArray([0xc0,0xaf]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80])]:
  t.test(not J.parse_bytes(invalid).ok,'strict invalid UTF8')
 t.test(J.parse_bytes('{"x":"\\ud83d\\ude42","y":1}'.to_utf8_buffer()).value.x=='🙂','surrogate pair accepted')
 t.test(not J.parse_bytes(('['.repeat(66)+'0'+']'.repeat(66)).to_utf8_buffer()).ok,'JSON depth budget')

 for bad in [PackedByteArray([0]),PackedByteArray([0x80]),PackedByteArray([0xc0,0xaf]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80]),PackedByteArray([0xe2,0x82])]:
  t.error(S.decode_utf8(bad),'INVALID_INPUT','native strict UTF8 decoder')
 t.test(S.decode_utf8(PackedByteArray(S.encode_utf8('漢字🙂'))) == '漢字🙂', 'strict UTF8 roundtrip')
 for marker in [0,1,1.0,"true",[],{},null]:
  var ordinary={"isSpecQRError":marker,"code":"ordinary data"}
  t.test(E.is_error(ordinary)==false,"nonboolean error marker is ordinary data")
  var ordinary_copy=E.copy_json_checked({"payload":ordinary,"tail":1})
  t.test(typeof(ordinary_copy)==TYPE_DICTIONARY and ordinary_copy.has("payload") and ordinary_copy.has("tail"),"ordinary error-marker data copies without runtime error")
 var sentinel={"payload":{"error":"SpecQRError","isSpecQRError":true,"code":"DATA","nested":[1,2]},"tail":[3]}
 var sentinel_copy=E.copy_json_checked(sentinel)
 t.test(typeof(sentinel_copy)==TYPE_DICTIONARY and sentinel_copy.has("payload") and sentinel_copy.has("tail"),"nested error-shaped data remains nested")
 t.test(sentinel_copy==sentinel,"error-shaped JSON data lossless")
 if sentinel_copy.has("payload"):
  sentinel_copy.payload.nested[0]=9
 t.test(sentinel.payload.nested[0]==1,"error-shaped JSON data independently owned")

 var raw_auto=P.run_request({'command':'raw','version':1,'ecc':'L','seed':2,'mask':'auto'})
 var raw_numeric=P.run_request({'command':'raw','version':1,'ecc':'L','seed':2,'mask':-1})
 t.test(not E.is_error(raw_auto) and raw_auto==raw_numeric,'raw auto maps to automatic mask')
 for seed in [11,63,64,100]:
  var raw=P.run_request({'command':'raw','version':1,'ecc':'L','seed':seed,'mask':0})
  var expected=PackedByteArray()
  for i in range(19): expected.append((i*149+43+seed*67)&255)
  t.test(not E.is_error(raw) and raw.data==expected.hex_encode(),'raw seed shift mathematical boundary '+str(seed))
