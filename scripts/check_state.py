import re, pathlib
# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
report = []
pattern = re.compile(r'^\s*@(?:State|StorageProp|StorageLink|Prop|Link|Provide|Consume)\s*(?:\([^)]*\))?\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*[:=]')
for p in sorted(root.rglob('*.ets')):
    lines = p.read_text().split('\n')
    for i, line in enumerate(lines):
        m = pattern.match(line)
        if not m:
            continue
        name = m.group(1)
        occ = 0
        for j, other in enumerate(lines):
            if j == i:
                continue
            if re.search(r'\b' + re.escape(name) + r'\b', other):
                occ += 1
        if occ == 0:
            report.append(f'{p}:{i+1} unused: {line.strip()}')
print('\n'.join(report) if report else 'no unused state')
print('total', len(report))
