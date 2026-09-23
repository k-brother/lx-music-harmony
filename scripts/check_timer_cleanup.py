#!/usr/bin/env python3
"""组件内定时器清理检查

页面/组件里 setTimeout / setInterval 用完不清理，组件销毁后回调仍会触发
（轻则白跑、重则操作已销毁的节点）。判定：文件里出现了定时器却没有对应的
clearTimeout / clearInterval。

用法：python3 scripts/check_timer_cleanup.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'


def main():
    problems = []
    for p in sorted(ROOT.rglob('*.ets')):
        text = p.read_text()
        # 只看组件文件（页面/自定义组件）
        if '@Component' not in text and 'struct ' not in text:
            continue
        sets = len(re.findall(r'\bsetTimeout\(', text))
        intervals = len(re.findall(r'\bsetInterval\(', text))
        clears = len(re.findall(r'\bclearTimeout\(', text))
        clear_intervals = len(re.findall(r'\bclearInterval\(', text))
        if sets and not clears:
            problems.append(f'{p.relative_to(ROOT)}: setTimeout x{sets} 但没有 clearTimeout')
        if intervals and not clear_intervals:
            problems.append(f'{p.relative_to(ROOT)}: setInterval x{intervals} 但没有 clearInterval')

    print('\n'.join(problems) if problems else 'no dangling timers')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
