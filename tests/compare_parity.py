import json, sys
js=json.load(open('/tmp/claude-0/parity/js.json')); gd=json.load(open('/tmp/claude-0/parity/gd.json'))
same=0; shown=0
for i,(a,b) in enumerate(zip(js,gd)):
    if a['log']==b['log'] and a['round']==b['round']: same+=1; continue
    if shown<3:
        shown+=1
        for k,(x,y) in enumerate(zip(a['log'],b['log'])):
            if x!=y:
                print('battle',i,'line',k); print(' JS:',x); print(' GD:',y); print(' prev:', a['log'][max(0,k-4):k]); break
        else: print('battle',i,'length differs',len(a['log']),len(b['log']), a['log'][len(b['log']):len(b['log'])+2], b['log'][len(a['log']):len(a['log'])+2])
print('identical logs:',same,'/',len(js))
