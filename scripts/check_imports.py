import re, pathlib

# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
problems = []
for p in sorted(root.rglob('*.ets')):
    text = p.read_text()
    lines = text.split('\n')
    imports = []  # (start_line, end_line, stmt)
    i = 0
    while i < len(lines):
        if lines[i].startswith('import '):
            start = i
            stmt = lines[i]
            while ';' not in stmt and i + 1 < len(lines):
                i += 1
                stmt += '\n' + lines[i]
            imports.append((start, i, stmt))
        i += 1
    for start, end, stmt in imports:
        names = []
        m = re.search(r'import\s+(?:type\s+)?\{([^}]*)\}', stmt, re.S)
        if m:
            for part in m.group(1).split(','):
                part = part.strip()
                if not part:
                    continue
                part = re.sub(r'^type\s+', '', part)
                if ' as ' in part:
                    part = part.split(' as ')[-1].strip()
                names.append(part)
        else:
            m2 = re.match(r"import\s+(?:type\s+)?([A-Za-z_$][A-Za-z0-9_$]*)", stmt)
            if m2:
                names.append(m2.group(1))
        for name in names:
            if not re.match(r'^[A-Za-z_$][A-Za-z0-9_$]*$', name):
                continue
            occurrences = 0
            for j, line in enumerate(lines):
                if start <= j <= end:
                    continue
                if re.search(r'\b' + re.escape(name) + r'\b', line):
                    occurrences += 1
            if occurrences == 0:
                problems.append(f'{p}:{start+1} unused import: {name}')

print('\n'.join(problems) if problems else 'no unused imports')
print(f'total: {len(problems)}')
