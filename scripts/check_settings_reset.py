#!/usr/bin/env python3
"""「恢复默认设置」完整性检查

SettingsService.resetToDefaults 手写了字段清单：AppSettings 新增字段时如果忘了加进去，
用户点了「恢复默认设置」却发现某些项没还原，而且没有任何报错。

这里要求：AppSettings 的每个字段要么出现在 resetToDefaults 里，要么列进保留名单
（保留的是用户身份/凭据类设置，静默清掉会很伤）。

用法：python3 scripts/check_settings_reset.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 有意保留：同步凭据与「已同意协议」不属于可调项
PRESERVED = {'syncEnabled', 'syncServer', 'syncKey', 'agreedPact'}


def main():
    types = (ROOT / 'service/settings/SettingsTypes.ets').read_text()
    block = re.search(r'export interface AppSettings \{(.*?)\n\}', types, re.S)
    if not block:
        print('FAIL 找不到 AppSettings 接口')
        return 1
    fields = re.findall(r'^\s{2}([A-Za-z_][\w]*)\??:', block.group(1), re.M)

    svc = (ROOT / 'service/SettingsService.ets').read_text()
    body_match = re.search(r'async resetToDefaults\(\): Promise<void> \{(.*?)\n  \}', svc, re.S)
    if not body_match:
        print('FAIL 找不到 resetToDefaults')
        return 1
    covered = set(re.findall(r'defaults\.([A-Za-z_][\w]*)', body_match.group(1)))

    missing = [f for f in fields if f not in covered and f not in PRESERVED]
    stale = sorted(PRESERVED - set(fields))
    print(f'AppSettings {len(fields)} 项，resetToDefaults 覆盖 {len(covered)} 项，'
          f'有意保留 {len(PRESERVED)} 项')
    if missing:
        print('FAIL 未还原且未列入保留名单:', missing)
    if stale:
        print('WARN 保留名单里的字段已不存在:', stale)
    if not missing:
        print('恢复默认设置覆盖完整')
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
