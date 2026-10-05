#!/usr/bin/env python3
"""Fail-closed real Godot verification against immutable source and all fixtures."""
import argparse,hashlib,json,pathlib,platform,subprocess,os,sys,time,re
from prepare_ci import verify
from native_support import require,binding,strict_json
from verification_support import runtime_environment
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',type=pathlib.Path,required=True);p.add_argument('--expect-version',choices=['4.3','4.7.2'],required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();a.godot=a.godot.resolve();a.output=a.output.resolve()
 require(not a.output.exists(),'Output must be a fresh directory');a.output.mkdir(parents=True)
 initial=verify(ROOT);pin=strict_json((ROOT/'verification/toolchains.json').read_bytes())['releases'][a.expect_version];require(binding(a.godot)['sha256']==pin['binarySha256'],'Godot executable is not the reviewed official build')
 report={'status':'running','runtime':binding(a.godot),'expectedVersion':a.expect_version,'host':{'os':platform.system(),'arch':platform.machine(),'python':platform.python_version()},'source':initial,'processes':[]};start=time.monotonic()
 env=runtime_environment();env.update(PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1',TZ='UTC',SPECQR_GODOT=str(a.godot));env.pop('PYTHONOPTIMIZE',None)
 def run(cmd,label,cwd=ROOT,stderr_empty=True,timeout=7200):
  log=a.output/(label+'.log');log.parent.mkdir(parents=True,exist_ok=True);started=time.monotonic();row={'label':label,'argv':[str(x) for x in cmd],'status':'running'};report['processes'].append(row)
  try:r=subprocess.run([str(x) for x in cmd],cwd=cwd,env=env,capture_output=True,timeout=timeout)
  except BaseException as error:row.update(status='failed',error=repr(error));raise
  log.write_bytes(r.stdout+b'\n--- stderr ---\n'+r.stderr)
  row.update(status='failed',exitCode=r.returncode,stdoutBytes=len(r.stdout),stderrBytes=len(r.stderr),stdoutSha256=hashlib.sha256(r.stdout).hexdigest(),stderrSha256=hashlib.sha256(r.stderr).hexdigest(),elapsedSeconds=round(time.monotonic()-started,3),log=binding(log))
  require(r.returncode==0,label+' failed: '+r.stderr.decode(errors='replace')[-2000:])
  if stderr_empty:require(not r.stderr,label+' unexpected stderr: '+r.stderr.decode(errors='replace')[-2000:])
  row['status']='passed';return r.stdout
 def godot(script,*args):return [a.godot,'--headless','--no-header','--path',ROOT,'--script',script,'--',*args]
 try:
  require(platform.system()=='Linux' and platform.machine() in ['x86_64','amd64'],'Reviewed execution profile is Linux x86-64')
  run([a.godot,'--headless','--no-header','--path',ROOT,'--editor','--import','--quit'],'editor-import',timeout=300)
  runtime=strict_json(run(godot(ROOT/'script/bridge.gd','--runtime'),'bridge-runtime'))
  actual='.'.join(str(runtime[k]) for k in ['major','minor']+(['patch'] if a.expect_version.count('.')==2 else []))
  require(actual==a.expect_version and runtime['status']=='stable' and runtime['os']=='Linux' and runtime['arch']=='x86_64' and runtime['nativeGDScript'] is True,'Unexpected native runtime');report['bridgeRuntime']=runtime
  harness=run([sys.executable,ROOT/'script/test_harness.py'],'harness-failure-controls');require(re.search(rb'Ran 35 tests in ',harness) and harness.rstrip().endswith(b'OK'),'Harness control cardinality changed');report['harnessControls']=35
  unit=strict_json(run(godot(ROOT/'tests/run_all.gd'),'native-unit'))
  require(unit.get('status')=='passed' and set(x['name'] for x in unit['groups'])=={'core','gs1','render','structured_append'} and unit['checks']==535,'Incomplete native unit groups');report['nativeUnits']=unit
  for script,key,expected in [('render_parity_test','checks',153),('api_sa_smoke','checked',57),('gs1_native_test','checks',303),('render_budget_test','checks',9),('optimizer_hardening','checked',149),('api_type_fuzz','checked',615),('native_keys','checks',34),('diagnostics_keys','checked',50),('gs1_url_compatibility','checks',332)]:
   extra=strict_json(run(godot(ROOT/('tests/'+script+'.gd')),script));require(extra.get(key)==expected and extra.get('failures')==[],'Incomplete '+script+' checks');report[script]=extra
  bridge=ROOT/'script/bridge.gd' 
  for suite in ['public','internal']:
   print('Running '+suite+' reference corpus',flush=True);run([sys.executable,ROOT/'script/verify_reference.py','--binary',bridge,'--suite',suite,'--timeout','7200','--output',a.output/(suite+'-reference.json')],suite+'-reference')
  for name in ['negative','gs1','wire']:
   run([sys.executable,ROOT/f'script/verify_{name}.py','--binary',bridge,'--output',a.output/(name+'.json')],name)
  for name in ['cli','consumer']:
   verifier=ROOT/f'script/verify_{name}.py';require(verifier.is_file(),'Missing required '+name+' verifier');summary=strict_json(run([sys.executable,verifier,'--godot',a.godot,'--output',a.output/name],name));require(summary.get('status')=='passed','Invalid '+name+' summary')
   if name=='cli':require(summary.get('cases')==38,'CLI cardinality changed')
   else:require(summary.get('scope')=='fresh-project-scene-and-native-image','Unexpected consumer scope')
  report['sourceStable']=verify(ROOT)==initial;require(report['sourceStable'],'Source changed');report['runtimeStable']=binding(a.godot)==report['runtime'];require(report['runtimeStable'],'Runtime executable changed');report['status']='passed'
 except BaseException as error:report.update(status='failed',error=repr(error));raise
 finally:report['elapsedSeconds']=round(time.monotonic()-start,3);(a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'godot':a.expect_version,'elapsedSeconds':report['elapsedSeconds']}))
if __name__=='__main__':main()
