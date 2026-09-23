#!/usr/bin/env python3
"""文件内重复代码块检查

`check_duplicate_impls.py` 找的是「整个函数体完全相同」，但更常见的是
「同一个文件里两个分支/两处 UI 复制了同一段 15 行左右的代码」——
例如排行榜的吸顶与未吸顶分支曾各写一份卡片列表（其中一份还漏了宽屏留白）。

做法：把每个文件按「非空非注释行」标准化，用 15 行滑动窗口找重复片段，
同一个重复区间只报一次（避免滑动窗口造成的大量重叠命中）。
纯数据表（core/theme/data、各源榜单名称表）按设计就高度重复，直接跳过。

用法：python3 scripts/check_duplicate_blocks.py
"""
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

WINDOW = 15
SKIP_PREFIX = ('core/theme/data/', 'core/music/sources/kw/leaderboard', 'core/music/sources/kg/leaderboard',
               'core/music/sources/tx/leaderboard', 'core/music/sources/wy/leaderboard',
               'core/music/sources/mg/leaderboard', 'core/music/sources/kw/songList',
               'core/music/sources/kg/songList', 'core/music/sources/tx/songList',
               'core/music/sources/wy/songList', 'core/music/sources/mg/songList')


def main():
    findings = []
    for p in sorted(ROOT.rglob('*.ets')):
        rel = str(p.relative_to(ROOT))
        if rel.startswith(SKIP_PREFIX):
            continue
        lines = [re.sub(r'\s+', ' ', l.strip()) for l in p.read_text().split('\n')]
        norm = list(lines)
        seen = {}
        reported_upto = -1
        i = 0
        while i < len(norm):
            if not norm[i] or norm[i].startswith('//'):
                i += 1
                continue
            if i <= reported_upto:
                i += 1
                continue
            block = []
            j = i
            while j < len(norm) and len(block) < WINDOW:
                if norm[j] and not norm[j].startswith('//'):
                    block.append(norm[j])
                j += 1
            if len(block) == WINDOW:
                key = hashlib.md5('\n'.join(block).encode()).hexdigest()
                if key in seen:
                    findings.append(f'{rel}: 第 {seen[key] + 1} 行与第 {i + 1} 行起有 {WINDOW} 行重复块')
                    reported_upto = i + WINDOW - 1
                else:
                    seen[key] = i
            i += 1

    print('\n'.join(findings) if findings else 'no duplicated blocks in same file')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
