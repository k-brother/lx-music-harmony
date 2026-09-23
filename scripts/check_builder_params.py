#!/usr/bin/env python3
"""回调属性里不许内联写组件（真机崩溃根因）。

真机抓到的崩溃（errorManager 兜底打出的栈）：

  TypeError: Cannot read property fontSize of undefined
    at trailing (src/main/ets/pages/LoveListPage.ts)
    at anonymous (src/main/ets/components/ui/NavBar.ts)

原因是把组件直接写在传给组件的箭头函数里：

  NavBar({
    trailing: (): void => {
      Text(tf('count_songs_short', [n])).fontSize(12)   // 不会被编译成 builder
    },
  })

ArkUI 只把 @Builder 方法调用编译成真正的 builder：箭头函数里的 Text(...) 运行时
返回 undefined，紧接的 .fontSize 抛 TypeError，整页崩溃。本地音乐页把
LocalMusicActions({...}) 内联在同一个位置，也是同一类崩溃。

正确写法：内容写成 @Builder 方法，回调里只调用它：

  trailing: (): void => { this.NavCount(); }

用法：python3 scripts/check_builder_params.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 属性值形态的箭头函数，例如 `trailing: (): void => {`
ARROW_START = re.compile(r"^\s*[A-Za-z_][\w]*\s*:\s*(?:async\s*)?\([^)]*\)\s*(?::[^=]*)?=>\s*\{\s*$")
# 内联组件调用，例如 `Text(` / `LocalMusicActions({`
INLINE_COMPONENT = re.compile(r"^\s*([A-Z][A-Za-z0-9_]*)\s*[({]")
ALLOWED = {'If', 'ForEach', 'LazyForEach', 'Repeat', 'While', 'Switch'}


def scan_file(path: pathlib.Path) -> list:
    problems = []
    lines = path.read_text().split('\n')
    depth = 0
    in_arrow = False
    arrow_line = 0
    for index, line in enumerate(lines, start=1):
        if not in_arrow:
            if ARROW_START.match(line):
                in_arrow = True
                arrow_line = index
                depth = 1
            continue
        depth += line.count('{') - line.count('}')
        match = INLINE_COMPONENT.match(line)
        if match:
            head = match.group(1)
            if head not in ALLOWED:
                problems.append(
                    f'{path.relative_to(ROOT.parent.parent)}:{arrow_line} 处的回调内联了组件 {head}()'
                    f'（第 {index} 行）；请改成 @Builder 方法后写 this.Xxx()')
                in_arrow = False
                continue
        if depth <= 0:
            in_arrow = False
    return problems


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob('*.ets')):
        problems.extend(scan_file(path))
    if problems:
        print('FAIL 回调属性里内联组件（真机会 TypeError 崩溃）:')
        print('\n'.join(problems))
        return 1
    print('回调属性写法正确（组件都在 @Builder 方法里）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
