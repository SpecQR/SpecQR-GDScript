extends RefCounted
const G=preload('../addons/specqr/gs1.gd')
const E=preload('../addons/specqr/error.gd')
static func run(t):
 var gtin='09506000134352'
 var primary={'ai':'01','value':gtin}
 var values=[primary,{'ai':'10','value':'LOT-A'},{'ai':'17','value':'271231'}]
 t.test(G.get_supported_gs1_ais().size()==50,'GS1 catalog cardinality')
 var catalog=G.get_supported_gs1_ais()
 catalog[0].length.exact=1
 t.test(G.get_gs1_ai_info('00').length.exact==18,'GS1 catalog copy')
 t.test(G.calculate_gs1_check_digit('0950600013435')=='2','GTIN check digit')
 t.test(G.validate_gtin_check_digit(gtin),'GTIN valid')
 t.test(not G.validate_gtin_check_digit('09506000134353'),'GTIN invalid')
 var raw=G.create_gs1_element_string(values)
 t.test(raw=='01'+gtin+'10LOT-A'+String.chr(29)+'17271231','GS1 separator exact')
 t.test(G.parse_gs1_element_string(raw).elements==values,'GS1 raw roundtrip')
 t.test(G.parse_gs1_human_readable('(01)'+gtin+'(10)LOT-A(17)271231')==values,'GS1 human roundtrip')
 for bad in [null,1,true,[],{},NAN]: t.error(G.calculate_gs1_check_digit(bad),'INVALID_GS1','GS1 scalar guard')
 t.error(G.parse_gs1_element_string('10LOT17271231'),'INVALID_GS1','separator ambiguity rejects')
 var link='https://example.com/01/'+gtin
 t.test(G.normalize_gs1_digital_link('HTTPS://EXAMPLE.COM:00443/01/'+gtin)==link,'URL canonical authority')
 for host in ['0x','0X','127.1','0177.0.0.1','user@example.com','%65xample.com','a..b']:
  var parsed=G.parse_gs1_digital_link('https://'+host+'/01/'+gtin)
  t.test(not E.is_error(parsed) and parsed.primary==primary,'current TypeScript authority accepted '+host)
 for host in ['1.2.3.256','example.0xff','example.123','[::1%25eth0]','[1::2::3]']:
  t.error(G.parse_gs1_digital_link('https://'+host+'/01/'+gtin),'INVALID_GS1','malformed authority rejected '+host)
 for bad in ['%','%GG','%C0%AF','%ED%A0%80','%F4%90%80%80','%00','%E2%82']:
  t.error(G.parse_gs1_digital_link(link+'?x='+bad),'INVALID_GS1','strict URL percent')
 var unknown=G.parse_gs1_digital_link(link+'?x=a+b&x=c%2Bd&empty')
 t.test(not E.is_error(unknown) and unknown.unknownQuery==[{'key':'x','value':'a b'},{'key':'x','value':'c+d'},{'key':'empty','value':''}],'ordered unknown query preservation')
