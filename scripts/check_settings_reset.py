#!/usr/bin/env python3
"""「恢复默认设置」完整性检查

SettingsService.resetToDefaults 手写了字段清单，两组错误都只有真机点到才发现：

1. **漏还原**：AppSettings 新增字段时忘了加进去，用户点了「恢复默认设置」却发现某项没还原；
2. **假保留**（B16）：字段既列在保留名单里、又出现在 resetToDefaults 里 —— 注释说「有意保留」、
   代码却把它清了。agreedPact（已同意许可协议）就栽在这上面：恢复默认设置后下次启动会重新弹协议，
   而注释和检查脚本都写着「有意保留」。

所以这里要求：
- AppSettings 的每个字段要么出现在 resetToDefaults 里，要么列进保留名单
  （保留的是用户身份/凭据/已同意状态，静默清掉很伤）；
- 两侧不允许重叠：既保留又还原 = 口径不一致，直接失败。

用法：python3 scripts/check_settings_reset.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 有意保留：同步/WebDAV 的账号与服务器配置、以及「已同意协议」，都不属于可调项
# （误触一次「恢复默认设置」就要重新配一遍，且凭据本体存在设置之外）
PRESERVED = {'syncEnabled', 'syncServer', 'syncKey', 'webdavUrl', 'webdavUser', 'agreedPact'}


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
    # 既在保留名单里、又被 resetToDefaults 还原 —— 口径矛盾（B16：agreedPact 就是这么错的）
    contradictory = sorted(PRESERVED & covered)
    print(f'AppSettings {len(fields)} 项，resetToDefaults 覆盖 {len(covered)} 项，'
          f'有意保留 {len(PRESERVED)} 项')
    if missing:
        print('FAIL 未还原且未列入保留名单:', missing)
    if contradictory:
        print('FAIL 既列入保留名单又被还原（口径矛盾，二者只能留一个）:', contradictory)
    if stale:
        print('WARN 保留名单里的字段已不存在:', stale)
    if not missing and not contradictory:
        print(f'恢复默认设置覆盖完整（保留 {sorted(PRESERVED)}）')
    return 1 if (missing or contradictory) else 0


if __name__ == '__main__':
    sys.exit(main())
