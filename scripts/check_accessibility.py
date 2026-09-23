#!/usr/bin/env python3
"""无障碍（屏幕朗读）检查

规则：**只有图标、没有文字的点击目标必须带 accessibilityText**，否则读屏用户听到
的是一片空白。真机上这类按钮集中在播放控制、导航返回、下载操作、列表「更多」等位置。

判定方式（保守）：从 `.onClick(` 往上找最近的容器开括号，看这段容器内容里
- 有 SymbolGlyph/Image（说明是图标按钮）
- 没有 Text(（说明没有可读文字）
- 也没有 accessibilityText
三者同时满足即报错。

用法：python3 scripts/check_accessibility.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 只把「组件/容器调用」当作块起点：`Row() {` / `SymbolGlyph(...)` 这类，
# 跳过 `if (...) {` / `for (...) {`，否则会把尾部条件块误当成点击目标的根
CONTAINER = re.compile(r'^\s*(?!if\b|for\b|while\b|switch\b|else\b)[A-Za-z_$][\w$.]*\s*\(.*\)\s*\{\s*$')


def main():
    problems = []
    total_targets = 0
    for p in sorted(ROOT.rglob('*.ets')):
        lines = p.read_text().split('\n')
        for i, line in enumerate(lines):
            if '.onClick(' not in line:
                continue
            total_targets += 1
            start = None
            for j in range(i - 1, max(-1, i - 40), -1):
                if CONTAINER.match(lines[j]):
                    start = j
                    break
            if start is None:
                continue
            block = lines[start:i + 1]
            has_icon = any(('SymbolGlyph(' in b) or ('Image(' in b) for b in block)
            has_text = any(re.search(r'\bText\(', b) for b in block)
            has_a11y = any('accessibilityText' in b for b in block)
            if has_icon and not has_text and not has_a11y:
                problems.append(f'{p.relative_to(ROOT)}:{i + 1}')

    print(f'点击目标 {total_targets} 个，其中「纯图标且无朗读文案」{len(problems)} 个')
    for item in problems:
        print('FAIL 图标按钮缺少 accessibilityText:', item)
    if not problems:
        print('无障碍检查通过')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
