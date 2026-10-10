#!/usr/bin/env python3
# Build a GitHub push_files payload with every text file changed since v0.16
# (plus /data/v17 notes/scripts) under v18_wip/ ; writes /data/v17/gh_payload.json
import os, filecmp, json, sys
msg = sys.argv[1] if len(sys.argv) > 1 else "v0.18 WIP backup"
base = '/data/r16/play/RoninsEdge'
root = '/data/ronins_edge'
TEXT = ('.gd', '.tscn', '.tres', '.gdshader', '.gdshaderinc', '.md', '.txt', '.cfg', '.godot', '.py', '.sh', '.json', '.svg')
files = []
for r, ds, fs in os.walk(os.path.join(root, 'game')):
    ds[:] = [d for d in ds if d not in ('.godot', '.git')]
    for f in fs:
        p = os.path.join(r, f)
        if f == 'override.cfg' or not f.endswith(TEXT):
            continue
        rel = os.path.relpath(p, os.path.join(root, 'game'))
        b = os.path.join(base, rel)
        if os.path.exists(b) and filecmp.cmp(p, b, shallow=False):
            continue
        files.append(('v18_wip/game/' + rel, p))
files.append(('v18_wip/tools/pack.py', os.path.join(root, 'tools/pack.py')))
for f in sorted(os.listdir('/data/v17')):
    p = os.path.join('/data/v17', f)
    if os.path.isfile(p) and f.endswith(('.md', '.sh', '.py')) and not f.startswith('gh_payload'):
        files.append(('v18_wip/notes/' + f, p))
for f in sorted(os.listdir('/data/v17/patch')) if os.path.isdir('/data/v17/patch') else []:
    files.append(('v18_wip/notes/patch/' + f, os.path.join('/data/v17/patch', f)))
man = '\n'.join(a for a, _ in files) + '\n'
out = [{'path': a, 'content': open(p, encoding='utf-8', errors='replace').read()} for a, p in files]
out.append({'path': 'v18_wip/MANIFEST.txt', 'content': 'Overlay on v0.16 play+dev zips: cp -a v18_wip/game/. /data/ronins_edge/game/ ; notes -> /data/v17\n' + man})
d = {'owner': 'arpan085', 'repo': 'ronins-edge', 'branch': 'v0.18-wip-backup', 'message': msg, 'files': out}
s = json.dumps(d)
open('/data/v17/gh_payload.json', 'w').write(s)
print(len(out), 'files', len(s), 'bytes')
