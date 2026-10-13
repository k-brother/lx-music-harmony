#!/usr/bin/env python3
"""原生源码在位守卫：内置的 QuickJS 源码必须真的在仓库里。

为什么要有这条：这个目录曾经是 git submodule，但 `.gitmodules` 没入库、gitlink 指向的
commit 在上游也不存在 —— 于是新克隆下来的工作区里 `quickjs_src/` 是个**空目录**，
CMake 直到 `add_library(quickjs_napi ...)` 才报 `No SOURCES given to target`，
排查成本全落在"为什么只有我这台机器能编过"上。

判据：
1. `entry/src/main/cpp/quickjs_src/` 下 CMake 要编的 5 个 .c 与它们 include 的头文件都在且非空；
2. 这些文件确实被 git 跟踪（本地有、别人克隆不到，等于没有）；
3. 该路径没有被记录成 gitlink（mode 160000）—— 那正是上面那个坑的形态。

用法：python3 scripts/check_native_sources.py
"""
import pathlib
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent
QUICKJS_REL = 'entry/src/main/cpp/quickjs_src'
QUICKJS_DIR = PROJECT / QUICKJS_REL

REQUIRED = [
    # CMake 编译的源文件
    'quickjs.c', 'cutils.c', 'dtoa.c', 'libunicode.c', 'libregexp.c',
    # 它们直接 include 的头文件
    'quickjs.h', 'quickjs-atom.h', 'quickjs-opcode.h',
    'cutils.h', 'dtoa.h', 'libregexp.h', 'libregexp-opcode.h',
    'libunicode.h', 'libunicode-table.h', 'list.h',
    # 许可与版本（内置第三方代码必须带）
    'LICENSE', 'Changelog',
]


def tracked(path: str) -> list:
    out = subprocess.run(['git', 'ls-files', '-s', '--', path],
                         cwd=PROJECT, capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def main() -> int:
    problems = []
    if not QUICKJS_DIR.is_dir():
        print(f'FAIL 内置原生源码目录缺失：{QUICKJS_REL}（新克隆会直接构建失败）')
        return 1

    for name in REQUIRED:
        f = QUICKJS_DIR / name
        if not f.exists():
            problems.append(f'{QUICKJS_REL}/{name} 不存在（构建会失败）')
        elif f.stat().st_size == 0:
            problems.append(f'{QUICKJS_REL}/{name} 是空文件（构建会失败）')

    entries = tracked(QUICKJS_REL)
    gitlinks = [e for e in entries if e.startswith('160000')]
    if gitlinks:
        problems.append(
            f'{QUICKJS_REL} 被记录成 gitlink（submodule）：{gitlinks}；'
            f'新克隆只会得到空目录，请把源码作为普通文件入库')

    tracked_names = {e.split('\t', 1)[-1].split('/')[-1] for e in entries}
    missing = [name for name in REQUIRED if name not in tracked_names]
    if missing:
        problems.append(
            f'这些文件在本机存在但没被 git 跟踪，别人克隆不到：{", ".join(missing)}')

    if problems:
        print('FAIL 内置原生源码不完整:')
        print('\n'.join(problems))
        return 1
    print(f'内置原生源码在位：{QUICKJS_REL}（{len(REQUIRED)} 个文件已入库）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
