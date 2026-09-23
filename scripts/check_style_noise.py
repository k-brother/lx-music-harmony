#!/usr/bin/env python3
"""通用属性链噪音检查

两类「看着能过、其实是漏改留下的痕迹」：
1. 同一段属性链里连续两行完全相同的通用属性（`.layoutWeight(1)` 连着写两遍）；
2. 第二行缩进反而比第一行更深（说明是补丁错位塞进去的，读起来像另一个组件
   的属性，实际却挂在同一个组件上）。

历史上 HistoryListPage / LoveListPage 的骨架分支就各留了一份这样的尾巴。

用法：python3 scripts/check_style_noise.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def main() -> int:
    findings = []
    for p in sorted(ROOT.rglob('*.ets')):
        lines = p.read_text().split('\n')
        rel = str(p.relative_to(ROOT))
        for i in range(len(lines) - 1):
            cur, nxt = lines[i], lines[i + 1]
            cur_body, nxt_body = cur.strip(), nxt.strip()
            if not cur_body.startswith('.') or not nxt_body.startswith('.'):
                continue
            if cur_body != nxt_body:
                continue
            kind = '缩进更深' if indent_of(nxt) > indent_of(cur) else '重复'
            findings.append(f'{rel}:{i + 1} 连续两行相同属性（{kind}）：{cur_body}')
    print('\n'.join(findings) if findings else 'no duplicated/indented modifiers')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
