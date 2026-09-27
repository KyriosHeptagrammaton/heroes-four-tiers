#!/usr/bin/env python3
"""Builds web/index.html (multi-file, for the launcher) and dist/heroes.html (single self-contained file)."""
import os, re, glob
ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, 'web')
js = sorted(os.path.basename(p) for p in glob.glob(os.path.join(WEB, 'js', '*.js')))
body = '''<div id="menu" class="screen"></div>
<div id="sandbox" class="screen"></div>
<div id="battle" class="screen"></div>
<div id="world" class="screen"></div>
<div id="town" class="screen full"></div>
<div id="armyscr" class="screen full"></div>
<div id="handoff" class="screen handoff"></div>
<div id="tip"></div>
<div id="modal-bg"><div id="modal"></div></div>
<div id="toast"></div>'''
head = '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Heroes of the Four Tiers</title>\n'
multi = head + '<link rel="stylesheet" href="styles.css">\n</head><body>\n' + body + '\n' + '\n'.join(f'<script src="js/{f}"></script>' for f in js) + '\n</body></html>\n'
open(os.path.join(WEB, 'index.html'), 'w').write(multi)
css = open(os.path.join(WEB, 'styles.css')).read()
scripts = '\n'.join('<script>\n' + open(os.path.join(WEB, 'js', f)).read().replace('</script>', '<\\/script>') + '\n</script>' for f in js)
single = head + '<style>\n' + css + '\n</style>\n</head><body>\n' + body + '\n' + scripts + '\n</body></html>\n'
os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
open(os.path.join(ROOT, 'dist', 'heroes.html'), 'w').write(single)
print('built', len(js), 'scripts;', len(single)//1024, 'KB single file')
