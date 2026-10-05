#!/usr/bin/env python3
"""Public headless CLI contracts, checked processes and native file outputs."""
import argparse,base64,hashlib,json,pathlib,subprocess,zlib,struct
from native_support import strict_json,binding,require
from prepare_ci import inventory
from verification_support import runtime_environment
ROOT=pathlib.Path(__file__).resolve().parents[1]

def check_png(data):
 require(data[:8]==b'\x89PNG\r\n\x1a\n','PNG signature');at=8;ids=[];raw=b'';width=height=None
 while at<len(data):
  require(at+12<=len(data),'PNG truncation');size=struct.unpack('>I',data[at:at+4])[0];tag=data[at+4:at+8];payload=data[at+8:at+8+size];end=at+12+size;require(end<=len(data),'PNG chunk truncation');require(zlib.crc32(tag+payload)&0xffffffff==struct.unpack('>I',data[end-4:end])[0],'PNG CRC');ids.append(tag)
  if tag==b'IHDR':width,height=struct.unpack('>II',payload[:8])
  if tag==b'IDAT':raw+=payload
  at=end
 require(ids[0]==b'IHDR' and ids[-1]==b'IEND' and at==len(data),'PNG chunk order');pixels=zlib.decompress(raw);require(len(pixels)==height*(width*4+1),'PNG raster length');return {'width':width,'height':height,'bytes':len(data)}

def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();out=a.output.resolve();require(not out.exists(),'CLI output must be fresh');out.mkdir(parents=True)
 before=inventory(ROOT);engine=str(pathlib.Path(a.godot).resolve());cmd=[engine,'--headless','--no-header','--path',str(ROOT),'--script','script/cli.gd','--'];env=runtime_environment();receipts=[]
 def call(args,success=True,code=None):
  run=subprocess.run(cmd+args,env=env,cwd=out,capture_output=True,timeout=60);stem='case-%03d'%len(receipts);(out/(stem+'.stdout')).write_bytes(run.stdout);(out/(stem+'.stderr')).write_bytes(run.stderr)
  if success:require(run.returncode==0 and not run.stderr,'CLI success failed '+repr(args)+': '+run.stderr[:500].decode(errors='replace'))
  else:
   require(run.returncode==2 and not run.stdout,'CLI failure contract '+repr(args));require(run.stderr.count(b'\n')==1 and run.stderr.startswith((code+': ').encode()),'CLI error class '+repr(args))
  receipts.append({'args':args,'exitCode':run.returncode,'stdout':binding(out/(stem+'.stdout')),'stderr':binding(out/(stem+'.stderr'))});return run.stdout
 text=out/'入力 🙂.txt';text.write_text('漢字 SpecQR 🙂',encoding='utf8');binary=out/'binary.bin';binary.write_bytes(bytes([0,255,128,1,0]))
 require(b'Godot' in call(['--help']),'Help');require(b'0.1.0' in call(['--version-info']),'Version')
 baseline=strict_json(call(['--text','HELLO 123','--format','json']));require(baseline['version']==1,'Auto version')
 require(strict_json(call(['--text','HELLO 123','--format','matrix']))==baseline['matrix'],'Matrix output')
 svg=call(['--text','HELLO 123']);require(svg.startswith(b'<svg') and svg.endswith(b'\n'),'SVG stdout')
 require(call(['--text','HELLO 123','--format','svg-data-url']).startswith(b'data:image/svg+xml;'),'SVG URL')
 dataurl=call(['--text','HELLO 123','--format','png-data-url']).strip();check_png(base64.b64decode(dataurl.split(b',',1)[1],validate=True))
 target=out/'画像 QR.png';require(not call(['--text-file',str(text),'--eci','26','--ecc','Q','--format','png','--output',str(target)]),'File output stdout');png=check_png(target.read_bytes())
 native=strict_json(call(['--bytes-file',str(binary),'--format','json']));require(native['diagnostics']['input_bytes']==5,'Opaque binary input')
 plan=strict_json(call(['--text','HELLO','--plan']));require(plan['ok'] and not plan['diagnostics']['codewords_built'] and not plan['diagnostics']['mask_evaluated'],'Arithmetic-only CLI plan')
 sa=strict_json(call(['--text','x'*100,'--version','1','--ecc','L','--structured-append','--format','json']));require(2<=sa['total']<=16 and len(sa['symbols'])==sa['total'],'SA output')
 call(['--text','A%BC','--fnc1','--format','json']);call(['--text','123','--fnc1-second','A','--format','json']);call(['--text','010950600013435210LOT1','--gs1','--format','json'])
 call(['--text','123','--no-optimize','--no-kanji','--boost','--margin','5','--scale','2','--print-dpi','300','--foreground','#123456','--background','#ffffff','--min-version','2','--max-version','3','--mask','7','--format','json'])
 failures=[([], 'INVALID_INPUT'),(['--bogus'],'INVALID_INPUT'),(['--bogus\nsecond-line\r\x1b[31m\u0085\u2028\u2029'],'INVALID_INPUT'),(['--text'],'INVALID_INPUT'),(['--text','x','--text','y'],'INVALID_INPUT'),(['--text','x','--version','0'],'INVALID_VERSION'),(['--text','x','--mask','8'],'INVALID_INPUT'),(['--text','x','--eci','-1'],'INVALID_ECI'),(['--text','x','--ecc','l'],'INVALID_ECC_LEVEL'),(['--text','x','--format','pdf'],'INVALID_OUTPUT'),(['--text','x','--format','png'],'INVALID_OUTPUT'),(['--text','x','--structured-append'],'INVALID_OUTPUT'),(['--text','x','--plan','--structured-append'],'INVALID_MODE'),(['--text','x','--print-dpi','NaN'],'INVALID_INPUT'),(['--text','x','--scale','1.5'],'INVALID_INPUT'),(['--text-file',str(out/'missing')],'IO_ERROR'),(['--text','x','--output',str(out/'missing/output')],'IO_ERROR')]
 for args,code in failures:call(args,False,code)
 for idx,raw in enumerate([b'\0',b'abc\0def',b'\xc0\xaf',b'\xed\xa0\x80',b'\xf4\x90\x80\x80',b'\xf0\x9f']):
  bad=out/('bad-%d.txt'%idx);bad.write_bytes(raw);call(['--text-file',str(bad)],False,'INVALID_INPUT')
 require(inventory(ROOT)==before,'Source changed during CLI verification');report={'status':'passed','cases':len(receipts),'sourceSha256':before,'engine':binding(engine),'png':png,'processes':receipts};(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':'passed','cases':len(receipts),'report':str(out/'report.json')}))
if __name__=='__main__':main()
