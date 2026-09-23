#!/usr/bin/env python3
"""路由一致性检查

1. 代码里 navigateTo(RouteName.X) 用到的路由，必须在 NavIndex.buildRouteMap 里有分支
   —— 否则点击后会跳到一个空页面（真机上表现为「点了没反应」）；
2. buildRouteMap 里的分支必须有对应的 RouteName（避免手写字符串漂移）；
3. 从未被使用的 RouteName 属于死枚举，也要清掉。

用法：python3 scripts/check_routes.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'


def main():
    nav = (ROOT / 'service/NavigationService.ets').read_text()
    enum_block = re.search(r'export enum RouteName \{(.*?)\n\}', nav, re.S)
    if not enum_block:
        print('FAIL 找不到 RouteName 枚举')
        return 1
    members = {}
    for line in enum_block.group(1).split('\n'):
        m = re.match(r"\s*([A-Z_]+)\s*=\s*'([^']+)'", line)
        if m:
            members[m.group(1)] = m.group(2)

    index = (ROOT / 'pages/NavIndex.ets').read_text()
    branch_block = re.search(r'buildRouteMap\(name: string\) \{(.*?)\n  \}', index, re.S)
    if not branch_block:
        print('FAIL 找不到 NavIndex.buildRouteMap')
        return 1
    branches = set(re.findall(r"name === '([^']+)'", branch_block.group(1)))

    all_text = '\n'.join(p.read_text() for p in ROOT.rglob('*.ets'))
    used = set(re.findall(r'RouteName\.([A-Z_]+)', all_text))

    missing_branch = sorted(name for name in used if name in members and members[name] not in branches)
    unknown_branch = sorted(v for v in branches if v not in members.values())
    unused = sorted(name for name in members if name not in used)

    print(f'RouteName {len(members)} 条，buildRouteMap 分支 {len(branches)} 个，代码中使用 {len(used)} 条')
    problems = 0
    if missing_branch:
        print('FAIL 使用了但没有页面分支:', missing_branch)
        problems += len(missing_branch)
    if unknown_branch:
        print('FAIL 分支没有对应 RouteName:', unknown_branch)
        problems += len(unknown_branch)
    if unused:
        print('FAIL 从未使用的 RouteName:', unused)
        problems += len(unused)
    if not problems:
        print('路由检查通过')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
