#!/usr/bin/env python3
"""播放队列落盘出口检查

「重启后队列还在」依赖每一处队列变更都调用 PlayerService.persistQueue()。
入口一分散就可能漏（改队列顺序、插队、自动清理各一处），漏了的现象只有真机重启才看得到，
所以用脚本把「变更点 ⇒ 落盘」钉成硬约束。

判定：PlayerService.ets 里凡是改 `this.playList` / `this.currentIndex` 的函数，
函数体内必须出现 `this.persistQueue()`。恢复类函数（从快照回填）与销毁流程不需要落盘。

用法：python3 scripts/check_queue_persist.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
TARGET = ROOT / 'service/PlayerService.ets'
# 这些函数是从快照恢复/清理状态，不需要回写队列
SKIP_FUNCS = {'restoreLastPlayback', 'restoreQueue', 'destroy', 'init', 'clearSavedPlayTime'}
MUTATIONS = (r'this\.playList\s*=', r'this\.playList\.splice\(', r'this\.currentIndex\s*=')
FUNC_EXP = re.compile(r'^\s{2}(?:private\s+|public\s+|static\s+)*(?:async\s+)?([A-Za-z_$][\w$]*)\s*\(')


def enclosing_function(lines: list, at: int) -> str:
    for i in range(at, -1, -1):
        m = FUNC_EXP.match(lines[i])
        if m:
            return m.group(1)
    return ''


def function_end(lines: list, start_marker: int) -> int:
    """从函数声明行往后找到大括号配平的结束行（够用的近似：按缩进回到 2 空格且以 } 开头）"""
    for i in range(start_marker + 1, len(lines)):
        if lines[i].startswith('  }'):
            return i
    return len(lines)


def main() -> int:
    lines = TARGET.read_text().split('\n')
    findings = []
    checked = set()
    for i, line in enumerate(lines):
        if not any(re.search(exp, line) for exp in MUTATIONS):
            continue
        name = enclosing_function(lines, i)
        if not name or name in SKIP_FUNCS or name in checked:
            continue
        checked.add(name)
        start = next(j for j in range(i, -1, -1) if FUNC_EXP.match(lines[j]))
        end = function_end(lines, start)
        body = '\n'.join(lines[start:end])
        if 'this.persistQueue()' not in body:
            findings.append(f'{name}(): 改动队列但没有调用 this.persistQueue()（重启后队列会丢）')
    for item in findings:
        print(item)
    print('checked functions', len(checked))
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
