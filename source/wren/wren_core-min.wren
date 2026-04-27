class Bool{
}
class Fiber{
}
class Fn{
}
class Null{
}
class Num{
}
class Sequence{
all(a){
var b=true
for(c in this){
b=a.call(c)
if(!b)return b
}
return b
}
any(a){
var b=false
for(c in this){
b=a.call(c)
if(b)return b
}
return b
}
contains(a){
for(b in this){
if(a==b)return true
}
return false
}
count{
var a=0
for(b in this){
a=a+1
}
return a
}
count(a){
var b=0
for(c in this){
if(a.call(c))b=b+1
}
return b
}
each(a){
for(b in this){
a.call(b)
}
}
isEmpty{iterate(null)?false:true}
map(a){MapSequence.new(this,a)}
skip(a){
if(!(a is Num)||!a.isInteger||a<0){
Fiber.abort("Count must be a non-negative integer.")
}
return SkipSequence.new(this,a)
}
take(a){
if(!(a is Num)||!a.isInteger||a<0){
Fiber.abort("Count must be a non-negative integer.")
}
return TakeSequence.new(this,a)
}
where(a){WhereSequence.new(this,a)}
reduce(a,b){
for(c in this){
a=b.call(a,c)
}
return a
}
reduce(a){
var b=iterate(null)
if(!b)Fiber.abort("Can't reduce an empty sequence.")
var c=iteratorValue(b)
while(b=iterate(b)){
c=a.call(c,iteratorValue(b))
}
return c
}
join(){join("")}
join(a){
var b=true
var c=""
for(d in this){
if(!b)c=c+a
b=false
c=c+d.toString
}
return c
}
toList{
var a=List.new()
for(b in this){
a.add(b)
}
return a
}
}
class MapSequence is Sequence{
construct new(a,b){
_sequence=a
_fn=b
}
iterate(a){_sequence.iterate(a)}
iteratorValue(a){_fn.call(_sequence.iteratorValue(a))}
}
class SkipSequence is Sequence{
construct new(a,b){
_sequence=a
_count=b
}
iterate(a){
if(a){
return _sequence.iterate(a)
}else{
a=_sequence.iterate(a)
var b=_count
while(b>0&&a){
a=_sequence.iterate(a)
b=b-1
}
return a
}
}
iteratorValue(a){_sequence.iteratorValue(a)}
}
class TakeSequence is Sequence{
construct new(a,b){
_sequence=a
_count=b
}
iterate(a){
if(!a)_taken=1 else _taken=_taken+1
return _taken>_count?null:_sequence.iterate(a)
}
iteratorValue(a){_sequence.iteratorValue(a)}
}
class WhereSequence is Sequence{
construct new(a,b){
_sequence=a
_fn=b
}
iterate(a){
while(a=_sequence.iterate(a)){
if(_fn.call(_sequence.iteratorValue(a)))break
}
return a
}
iteratorValue(a){_sequence.iteratorValue(a)}
}
class String is Sequence{
bytes{StringByteSequence.new(this)}
codePoints{StringCodePointSequence.new(this)}
split(a){
if(!(a is String)||a.isEmpty){
Fiber.abort("Delimiter must be a non-empty string.")
}
var b=[]
var c=0
var d=0
var e=a.byteCount_
var f=byteCount_
while(c<f&&(d=indexOf(a,c))!=-1){
b.add(this[c...d])
c=d+e
}
if(c<f){
b.add(this[c..-1])
}else{
b.add("")
}
return b
}
replace(a,b){
if(!(a is String)||a.isEmpty){
Fiber.abort("From must be a non-empty string.")
}else if(!(b is String)){
Fiber.abort("To must be a string.")
}
var c=""
var d=0
var e=0
var f=a.byteCount_
var g=byteCount_
while(d<g&&(e=indexOf(a,d))!=-1){
c=c+this[d...e]+b
d=e+f
}
if(d<g)c=c+this[d..-1]
return c
}
trim(){trim_("\t\r\n ",true,true)}
trim(a){trim_(a,true,true)}
trimEnd(){trim_("\t\r\n ",false,true)}
trimEnd(a){trim_(a,false,true)}
trimStart(){trim_("\t\r\n ",true,false)}
trimStart(a){trim_(a,true,false)}
trim_(a,b,c){
if(!(a is String)){
Fiber.abort("Characters must be a string.")
}
var d=a.codePoints.toList
var e
if(b){
while(e=iterate(e)){
if(!d.contains(codePointAt_(e)))break
}
if(e==false)return ""
}else{
e=0
}
var f
if(c){
f=byteCount_-1
while(f>=e){
var g=codePointAt_(f)
if(g!=-1&&!d.contains(g))break
f=f-1
}
if(f<e)return ""
}else{
f=-1
}
return this[e..f]
}
*(a){
if(!(a is Num)||!a.isInteger||a<0){
Fiber.abort("Count must be a non-negative integer.")
}
var b=""
for(c in 0...a){
b=b+this
}
return b
}
}
class StringByteSequence is Sequence{
construct new(a){_string=a}
[a]{_string.byteAt_(a)}
iterate(a){_string.iterateByte_(a)}
iteratorValue(a){_string.byteAt_(a)}
count{_string.byteCount_}
}
class StringCodePointSequence is Sequence{
construct new(a){_string=a}
[a]{_string.codePointAt_(a)}
iterate(a){_string.iterate(a)}
iteratorValue(a){_string.codePointAt_(a)}
count{_string.count}
}
class List is Sequence{
addAll(a){
for(b in a){
add(b)
}
return a
}
sort(){sort{|a,b|a<b}}
sort(a){
if(!(a is Fn)){
Fiber.abort("Comparer must be a function.")
}
quicksort_(0,count-1,a)
return this
}
quicksort_(a,b,c){
if(a<b){
var d=partition_(a,b,c)
quicksort_(a,d-1,c)
quicksort_(d+1,b,c)
}
}
partition_(a,b,c){
var d=this[b]
var e=a-1
for(g in a..b-1){
if(c.call(this[g],d)){
e=e+1
var h=this[e]
this[e]=this[g]
this[g]=h
}
}
var f=this[e+1]
this[e+1]=this[b]
this[b]=f
return e+1
}
toString{"[%(join(", "))]"}
+(a){
var b=this[0..-1]
for(c in a){
b.add(c)
}
return b
}
*(a){
if(!(a is Num)||!a.isInteger||a<0){
Fiber.abort("Count must be a non-negative integer.")
}
var b=[]
for(c in 0...a){
b.addAll(this)
}
return b
}
}
class Map is Sequence{
keys{MapKeySequence.new(this)}
values{MapValueSequence.new(this)}
toString{
var a=true
var b="{"
for(key in keys){
if(!a)b=b+", "
a=false
b=b+"%(key): %(this[key])"
}
return b+"}"
}
iteratorValue(a){
return MapEntry.new(keyIteratorValue_(a),valueIteratorValue_(a))
}
}
class MapEntry{
construct new(a,b){
_key=a
_value=b
}
key{_key}
value{_value}
toString{"%(_key):%(_value)"}
}
class MapKeySequence is Sequence{
construct new(a){_map=a}
iterate(a){_map.iterate(a)}
iteratorValue(a){_map.keyIteratorValue_(a)}
}
class MapValueSequence is Sequence{
construct new(a){_map=a}
iterate(a){_map.iterate(a)}
iteratorValue(a){_map.valueIteratorValue_(a)}
}
class Range is Sequence{
}
class System{
static print(){writeString_("\n")}
static print(a){
writeObject_(a)
writeString_("\n")
return a
}
static printAll(a){
for(b in a)writeObject_(b)
writeString_("\n")
}
static write(a){
writeObject_(a)
return a
}
static writeAll(a){
for(b in a)writeObject_(b)
}
static writeObject_(a){
var b=a.toString
if(b is String){
writeString_(b)
}else{
writeString_("[invalid toString]")
}
}
}
class ClassAttributes{
self{_attributes}
methods{_methods}
construct new(a,b){
_attributes=a
_methods=b
}
toString{"attributes:%(_attributes) methods:%(_methods)"}
}