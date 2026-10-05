extends RefCounted
const SA=preload('../addons/specqr/structured_append.gd')
const E=preload('../addons/specqr/error.gd')
const S=preload('../addons/specqr/segments.gd')
static func run(t):
 t.test(SA.calculate_structured_append_parity('ABC')==64,'SA text parity')
 t.test(SA.calculate_structured_append_parity([0,255,1])==254,'SA byte parity with NUL')
 var text='ABCDEFGHIJKLMNOPQRSTUVWXYZ'.repeat(3)
 var set=SA.generate_structured_append(text,{'version':1,'errorCorrectionLevel':'M'},16,true)
 t.test(not E.is_error(set),'native SA generation')
 if E.is_error(set): return
 t.test(set.total>=2 and set.total<=16 and set.inputLength==text.length(),'SA count metadata')
 t.test(set.parity==SA.calculate_structured_append_parity(text),'SA parity metadata')
 var parts=[]
 for i in range(set.symbols.size()):
  var q=set.symbols[i]
  var detail=set.diagnostics.symbols[i]
  t.test(q.segments[0].mode=='structured-append' and q.segments[0].index==i+1 and q.segments[0].total==set.total and q.segments[0].parity==set.parity,'SA header ordering')
  parts.append({'index':i+1,'total':set.total,'parity':set.parity,'data':text.substr(detail.input_start,detail.input_length)})
 parts.reverse()
 t.test(SA.merge_structured_append_parts(parts).data==text,'SA reverse merge')
 for i in range(parts.size()):
  parts.append(parts.pop_front())
  t.test(SA.merge_structured_append_parts(parts).data==text,'SA rotate shuffle merge')
 var duplicate=parts.duplicate(true)
 duplicate.append(parts[0])
 t.error(SA.merge_structured_append_parts(duplicate),'INVALID_INPUT','duplicate SA index')
 var missing=parts.duplicate(true)
 missing.pop_back()
 t.error(SA.merge_structured_append_parts(missing),'INVALID_INPUT','missing SA index')
 var corrupt=parts.duplicate(true)
 corrupt[0].parity^=1
 t.error(SA.merge_structured_append_parts(corrupt),'INVALID_INPUT','corrupt SA parity')
 corrupt=parts.duplicate(true)
 corrupt[0].data+='a'
 t.error(SA.merge_structured_append_parts(corrupt),'INVALID_INPUT','corrupt SA data')
 var bytes=[]
 for i in range(256): bytes.append(i)
 var binary=SA.generate_structured_append(bytes,{'version':2,'errorCorrectionLevel':'L'},16)
 t.test(not E.is_error(binary),'SA all256 byte generation')
 if not E.is_error(binary):
  var bparts=[]
  for i in range(binary.symbols.size()):
   var detail=binary.diagnostics.symbols[i]
   bparts.append({'index':i+1,'total':binary.total,'parity':binary.parity,'data':bytes.slice(detail.input_start,detail.input_start+detail.input_length)})
  bparts.reverse()
  t.test(SA.merge_structured_append_parts(bparts).data==bytes,'SA all256 bytes shuffle merge')
 for value in ['', 'A']:
  t.error(SA.generate_structured_append(value),'INVALID_INPUT','SA single/empty reject')
 for opts in [{'fnc1':true},{'eci':26},{'fnc1Second':'A'},{'boostErrorCorrection':true}]:
  t.error(SA.generate_structured_append(text,opts),'INVALID_MODE','SA incompatible control')
 t.error(SA.generate_structured_append(text,{'gs1':true}),'INVALID_GS1','SA GS1 forbidden')
