#!/usr/bin/env python3
"""Fresh-project drop-in import, real scene execution and exact Image pixels."""
import argparse,hashlib,json,pathlib,shutil,subprocess
from native_support import strict_json,binding,require
from prepare_ci import inventory
from verification_support import runtime_environment
ROOT=pathlib.Path(__file__).resolve().parents[1]

def run(cmd,env,out,stem,timeout=180):
 r=subprocess.run(cmd,env=env,capture_output=True,timeout=timeout)
 (out/(stem+'.stdout')).write_bytes(r.stdout);(out/(stem+'.stderr')).write_bytes(r.stderr)
 require(r.returncode==0,stem+' process failed: '+r.stderr[:1000].decode(errors='replace'))
 require(not r.stdout and not r.stderr,stem+' unexpected stdout/stderr')
 return {'argv':cmd,'exitCode':r.returncode,'stdout':binding(out/(stem+'.stdout')),'stderr':binding(out/(stem+'.stderr'))}

def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 out=a.output.resolve();require(not out.exists(),'Consumer output must be fresh');out.mkdir(parents=True)
 engine=str(pathlib.Path(a.godot).resolve());before=inventory(ROOT);env=runtime_environment();env['GODOT_SILENCE_ROOT_WARNING']='1'
 project=out/'fresh-project';shutil.copytree(ROOT/'examples/consumer_project',project,ignore=shutil.ignore_patterns('.godot','*.gd.uid'));shutil.copytree(ROOT/'addons/specqr',project/'addons/specqr',ignore=shutil.ignore_patterns('*.gd.uid'))
 copied={str(p.relative_to(project/'addons/specqr')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (project/'addons/specqr').rglob('*') if p.is_file()}
 expected={k.removeprefix('addons/specqr/'):v for k,v in before.items() if k.startswith('addons/specqr/')};require(copied==expected,'Drop-in library differs')
 commands=[];base=[engine,'--quiet','--headless','--path',str(project)]
 commands.append(run(base+['--editor','--import','--quit'],env,out,'import'))
 result=out/'scene.json';env['SPECQR_CONSUMER_REPORT']=str(result);env['SPECQR_CONSUMER_PNG']=str(out/'scene.png')
 commands.append(run(base,env,out,'scene'))
 require(result.is_file(),'Scene did not emit report');data=strict_json(result.read_bytes());require(data.get('status')=='passed' and data.get('failures')==[],'Scene report failed');require(data.get('checks')==17,'Incomplete scene checks')
 require(data.get('imagePixelsMatched') is True and data.get('gpuTextureTested') is False,'Native Image evidence scope mismatch')
 require((out/'scene.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'),'Consumer PNG missing')
 require(inventory(ROOT)==before,'Source changed during consumer verification')
 report={'status':'passed','scope':'fresh-project-scene-and-native-image','gpuTexture':'not part of initial public API; no GPU readback claim','sourceSha256':before,'engine':binding(engine),'copiedLibrarySha256':copied,'commands':commands,'result':data,'sceneReport':binding(result),'png':binding(out/'scene.png')}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':'passed','scope':report['scope'],'report':str(out/'report.json')}))
if __name__=='__main__':main()
