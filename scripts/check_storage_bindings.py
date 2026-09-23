#!/usr/bin/env python3
"""AppStorage 绑定闭环检查

`@StorageProp('x')` / `@StorageLink('x')` 只有在有人 `AppStorage.setOrCreate('x', ...)`
时才会更新；绑定了一个没人写入的键，组件会永远停在初始值（真机上表现为
「改了设置界面不变」，而且没有任何报错）。

这里要求：代码里出现过的每个 storage 键都必须有写入方；
同时把「写入但没人读」的键作为提示打印出来（用于收敛无用的镜像）。

用法：python3 scripts/check_storage_bindings.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 由框架/能力注入而非应用写入的键
EXTERNAL = {'windowStage'}


def main():
    all_text = '\n'.join(p.read_text() for p in ROOT.rglob('*.ets'))
    bound = set(re.findall(r"@Storage(?:Prop|Link)\('([^']+)'\)", all_text))
    written = set(re.findall(r"AppStorage\.setOrCreate\('([^']+)'", all_text))
    read_directly = set(re.findall(r"AppStorage\.get<[^>]*>\('([^']+)'\)", all_text))
    read_directly |= set(re.findall(r"AppStorage\.get\('([^']+)'\)", all_text))

    consumers = bound | read_directly
    missing_writer = sorted(k for k in consumers if k not in written and k not in EXTERNAL)
    unused_mirror = sorted(k for k in written if k not in consumers)

    print(f'storage 键：绑定 {len(bound)}，直接读取 {len(read_directly)}，写入 {len(written)}')
    if missing_writer:
        print('FAIL 有人读取但没人写入（组件会永远停在初始值）:', missing_writer)
    if unused_mirror:
        print(f'NOTE 有人写入但没人读取（{len(unused_mirror)} 个，可考虑移除）:', unused_mirror)
    if not missing_writer:
        print('AppStorage 绑定闭环通过')
    return 1 if missing_writer else 0


if __name__ == '__main__':
    sys.exit(main())
