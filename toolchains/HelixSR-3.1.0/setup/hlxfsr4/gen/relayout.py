# relayout.py IN.hlsl OUT.hlsl : 1080p-layout kernel -> generic 4K-max layout (used for 1440p/4K)
import re,sys
M=[('15392','30752'),('7712','15392'),('8342464','33273664'),('16684928','66547328'),('2097664','8342464'),
   ('540u','1080u'),('960u','1920u'),('480u','960u'),('g.x==29','g.x==59'),('g.y==134','g.y==269'),('18782592','74889792')]
out=[]
for l in open(sys.argv[1]).read().split('\n'):
    if l.startswith('static const'): out.append(l); continue
    for i,(a,b) in enumerate(M): l=re.sub(r'(?<![0-9])'+re.escape(a)+r'(?![0-9])','@@%d@@'%i,l)
    for i,(a,b) in enumerate(M): l=l.replace('@@%d@@'%i,b)
    out.append(l)
open(sys.argv[2],'w').write('\n'.join(out)); print('ok')
