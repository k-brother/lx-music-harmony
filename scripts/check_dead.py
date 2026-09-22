import re, pathlib

# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
report = []
for p in sorted(root.rglob('*.ets')):
    text = p.read_text()
    lines = text.split('\n')
    # private methods & module-level functions
    for i, line in enumerate(lines):
        m = re.search(r'^\s*(?:private\s+|export\s+)?(?:async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\(', line)
        if not m:
            continue
        name = m.group(1)
        if name in ('if','for','while','switch','catch','return','function','constructor','get','set','describe'):
            continue
        if '=>' in line and 'function' not in line:
            continue
        if not (line.strip().startswith('private ') or line.strip().startswith('function ') or line.strip().startswith('export function')):
            continue
        occurrences = 0
        for j, other in enumerate(lines):
            if j == i:
                continue
            if re.search(r'\b' + re.escape(name) + r'\b', other):
                occurrences += 1
        if occurrences == 0:
            report.append(f'{p}:{i+1} unreferenced: {line.strip()[:90]}')

print('\n'.join(report) if report else 'no unreferenced private/function declarations')
print('total', len(report))
