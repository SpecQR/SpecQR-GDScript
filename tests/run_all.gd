extends SceneTree
const Check=preload('check.gd')
const Groups=[preload('core.gd'),preload('gs1.gd'),preload('render.gd'),preload('structured_append.gd')]
const Names=['core','gs1','render','structured_append']
func _initialize():
 var result={'status':'passed','checks':0,'groups':[]}
 for i in range(Groups.size()):
  var check=Check.new()
  Groups[i].run(check)
  result.checks+=check.checks
  result.groups.append({'name':Names[i],'checks':check.checks,'failures':check.failures,'status':'passed' if check.failures.is_empty() else 'failed'})
  if not check.failures.is_empty(): result.status='failed'
 print(JSON.stringify(result))
 quit(0 if result.status=='passed' else 1)
