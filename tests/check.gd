extends RefCounted
var checks=0
var failures=[]
func test(value,label):
 checks+=1
 if not value: failures.append(label)
func error(value,code,label):
 test(typeof(value)==TYPE_DICTIONARY and value.get('error')=='SpecQRError' and value.get('isSpecQRError')==true and value.get('code')==code,label)
