"""系统符号渲染检查

`Image($r('sys.symbol.xxx'))` 在真机上不会渲染任何内容（系统符号是字体字形资源，
必须用 SymbolGlyph）。历史上一度全项目 47 个图标因此隐形，这里做静态防回归。

退出码：发现违规用法返回 1。
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
PATTERN = re.compile(r"Image\(\s*\$r\('sys\.symbol\.")

violations = []
for path in sorted(root.rglob('*.ets')):
    for index, line in enumerate(path.read_text().split('\n'), start=1):
        if PATTERN.search(line):
            violations.append(f'{path.relative_to(root)}:{index}: {line.strip()}')

for item in violations:
    print('FAIL', item)
print()
print('Image 加载系统符号的用法：', len(violations), '（应为 0，系统符号请用 SymbolGlyph）')
sys.exit(1 if violations else 0)
