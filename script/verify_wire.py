#!/usr/bin/env python3
"""Actual Godot stdin/JSON framing, bounded malformed input and final EOF checks."""
import argparse,json,pathlib,subprocess,time,hashlib
from verification_support import binary_command,runtime_environment,snapshot,interpreter_binding
from native_support import require,strict_json
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--binary',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();a.output.parent.mkdir(parents=True,exist_ok=True)
 report={'status':'running','sourceSha256':snapshot(),'interpreter':interpreter_binding(),'cases':[]};cmd=binary_command(a.binary)
 cases=[('empty-stream',b'',0,False),('blank-line',b'\n',1,True),('malformed',b'{\n',1,True),('duplicate',b'{"text":"A","text":"B"}\n',1,True),('surrogate',b'{"text":"\\ud800"}\n',1,True),('nul-host',b'{"text":"a\\u0000b"}\n',1,True),('nonfinite',b'{"text":"A","x":1e999}\n',1,True),('trailing-comma',b'{"text":"A",}\n',1,True),('depth',b'['*66+b'0'+b']'*66+b'\n',1,True),('trailing-no-newline',b'{"text":"A"}',1,False),('ascii-chunks',json.dumps({'text':'A'*2200,'options':{'mode':'byte'}}).encode()+b'\n',1,False),('crlf',b'{"text":"A"}\r\n{"text":"B"}\r\n',2,False),('oversize-recovery',b' '*((16*1024*1024)+1)+b'\n{"text":"A"}\n',2,None)]
 try:
  for name,data,count,error in cases:
   started=time.monotonic();r=subprocess.run(cmd,input=data,capture_output=True,env=runtime_environment(),cwd=ROOT,timeout=120)
   row={'name':name,'exitCode':r.returncode,'stdinBytes':len(data),'stdinSha256':hashlib.sha256(data).hexdigest(),'stdoutBytes':len(r.stdout),'stdoutSha256':hashlib.sha256(r.stdout).hexdigest(),'stderrBytes':len(r.stderr),'stderrSha256':hashlib.sha256(r.stderr).hexdigest(),'elapsedSeconds':round(time.monotonic()-started,3),'status':'running'};report['cases'].append(row)
   require(r.returncode==0 and not r.stderr,name+' native failure/stderr: '+r.stderr.decode(errors='replace')[-2000:]);lines=r.stdout.splitlines();require(len(lines)==count,name+' response cardinality');rows=[strict_json(x) for x in lines]
   for i,out in enumerate(rows):
    want=(i==0) if error is None else error
    require((out.get('isSpecQRError') is True)==want,name+' unexpected result category')
    if want:require(out.get('code')=='INVALID_INPUT',name+' unexpected typed error')
   row['status']='passed'
  report['sourceStable']=snapshot()==report['sourceSha256'];require(report['sourceStable'],'Source changed');report['status']='passed'
 except BaseException as error:report.update(status='failed',error=repr(error));raise
 finally:a.output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'cases':len(report['cases'])}))
if __name__=='__main__':main()
