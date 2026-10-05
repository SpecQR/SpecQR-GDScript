extends SceneTree
const E = preload("../addons/specqr/error.gd")
const R = preload("../addons/specqr/render.gd")
const G = preload("../addons/specqr/gs1.gd")
const A = preload("../addons/specqr/api.gd")
var checks = 0
var failures = []
func check(condition, label):
 checks += 1
 if not condition: failures.append(label)
func strings_only(tree):
 if typeof(tree) == TYPE_DICTIONARY:
  for key in tree:
   if typeof(key) != TYPE_STRING or not strings_only(tree[key]): return false
 if typeof(tree) == TYPE_ARRAY:
  for item in tree:
   if not strings_only(item): return false
 return true
func _initialize():
 var qr=A.generate("HELLO")
 var elements=[{"ai":"01","value":"09506000134352"},{"ai":"10","value":"LOT"}]
 var input={StringName("nested"):{StringName("leaf"):[1,2]},StringName("flag"):true}
 var copied=E.copy_json_checked(input)
 check(not E.is_error(copied), "StringName JSON keys accepted")
 check(strings_only(copied), "Copied keys normalized to String")
 check(copied.nested.leaf==[1,2] and copied.flag, "Copied values exact")
 copied.nested.leaf[0]=7
 check(input.nested.leaf[0]==1, "Name-keyed copy independent")
 check(E.is_error(E.copy_json_checked(StringName("value"))), "StringName values remain strict")
 for key in [1, true, Vector2.ONE, RefCounted.new(), [], {}]:
  check(E.is_error(E.copy_json_checked({key:1})), "Nontext diagnostic key rejected")
  check(E.is_error(R.geometry(qr, {key:1})), "Nontext render key rejected")
  check(E.is_error(G.create_gs1_digital_link(elements, {key:1})), "Nontext GS1 key rejected")
 var named={StringName("margin"):2,StringName("scale"):3,StringName("foreground"):"#123456",StringName("background"):"#ffffff"}
 var ordinary={"margin":2,"scale":3,"foreground":"#123456","background":"#ffffff"}
 check(R.to_png(qr,named)==R.to_png(qr,ordinary), "Named render options exact PNG")
 check(R.to_svg(qr,named)==R.to_svg(qr,ordinary), "Named render options exact SVG")
 var dotted={}
 dotted.margin=2
 dotted.scale=3
 dotted.foreground="#123456"
 dotted.background="#ffffff"
 check(R.to_png(qr,dotted)==R.to_png(qr,ordinary), "Dot-created render options")
 var name_opts={StringName("pathAis"):[],StringName("explicitPathAis"):true}
 check(G.create_gs1_digital_link(elements,name_opts)==G.create_gs1_digital_link(elements,{"pathAis":[],"explicitPathAis":true}), "Named GS1 options")
 var dot_opts={}
 dot_opts.pathAis=[]
 dot_opts.explicitPathAis=true
 check(G.create_gs1_digital_link(elements,dot_opts)==G.create_gs1_digital_link(elements,{"pathAis":[],"explicitPathAis":true}), "Dot-created GS1 options")
 check(E.is_error(R.to_svg(qr,{StringName("unknown"):true})), "Unknown named render key")
 check(E.is_error(G.create_gs1_digital_link(elements,{StringName("unknown"):true})), "Unknown named GS1 key")
 check(E.is_error(R.to_png(qr,{StringName("foreground"):StringName("black")})), "Color values stay String-only")
 check(E.is_error(G.create_gs1_digital_link(elements,{StringName("explicitPathAis"):1})), "Boolean values stay strict")
 for key in [StringName("errorCorrectionLevel"),"errorCorrectionLevel"]:
  check(E.is_error(A.generate("A",{key:StringName("L")})), "ECC values stay String-only")
 print(JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
