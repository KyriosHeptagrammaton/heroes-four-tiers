import json
a=json.load(open('/tmp/claude-0/parity/world_js.json')); b=json.load(open('/tmp/claude-0/parity/world_gd.json'))
def norm(v):
    if isinstance(v,float) and v==int(v): return int(v)
    if isinstance(v,dict): return {k:norm(x) for k,x in v.items() if not (k=='special' and x is False)}
    if isinstance(v,list): return [norm(x) for x in v]
    return v
for s in a:
    A=norm(a[s]); B=norm(b[s]); bad=0
    for i,(ca,cb) in enumerate(zip(A['map']['cards'],B['map']['cards'])):
        if ca!=cb:
            bad+=1
            if bad<3: print(s,i,ca,'\n   ',cb)
    print(s,'cards diff',bad,'towns',A['towns']==B['towns'],'trans',A['trans']==B['trans'],'starts',A['starts']==B['starts'])
