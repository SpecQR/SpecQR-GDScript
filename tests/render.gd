extends RefCounted
const A=preload('../addons/specqr/api.gd')
const R=preload('../addons/specqr/render.gd')
const E=preload('../addons/specqr/error.gd')
static func run(t):
 var q=A.generate('Render native',{'version':2,'maskPattern':0})
 t.test(not E.is_error(q),'render source generation')
 if E.is_error(q): return
 var png=R.to_png(q)
 t.test(typeof(png)==TYPE_PACKED_BYTE_ARRAY and png.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]),'native PNG signature')
 if typeof(png)!=TYPE_PACKED_BYTE_ARRAY: return
 var image=Image.new()
 t.test(image.load_png_from_buffer(png)==OK,'native Godot PNG decode')
 t.test(image.get_width()==(q.matrix.size()+8)*8 and image.get_height()==image.get_width(),'default scale8 margin4 geometry')
 var svg=R.to_svg(q)
 t.test(typeof(svg)==TYPE_STRING and svg.begins_with('<svg') and svg.contains('viewBox='),'native SVG')
 t.test(R.to_png_data_url(q).begins_with('data:image/png;base64,'),'PNG data URL')
 t.test(R.to_svg_data_url(q).begins_with('data:image/svg+xml'),'SVG data URL')
 for color in ['','<script>','#ggg','url(x)','x'.repeat(65)]:
  t.error(R.to_png(q,{'foreground':color}),'INVALID_COLOR','invalid render color')
 for scale in [0,-1,1.5,true,'8',1000000001]:
  t.error(R.to_png(q,{'scale':scale}),'INVALID_INPUT','invalid render scale')
 var broken=q.duplicate(true)
 broken.matrix=[[0,1]]
 t.error(R.to_png(broken),'INVALID_INPUT','invalid render matrix')
