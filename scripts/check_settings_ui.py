#!/usr/bin/env python3
"""设置项「有入口 / 有人读」检查

两类很隐蔽的功能缺失：
1. 设置项没有 UI 入口 —— 字段存在、落盘也有，但用户永远改不到
   （本轮前面的逐字歌词就是这样：先加了字段，入口还没接上）；
2. 设置项没人读 —— 开关拨来拨去，播放/列表侧根本不看它。

判定（只看 UI 层文件，settings 基础设施本身不算）：
- 写入：字段名出现在 `update({ field: ... })` 字面量里，或 `SettingsPatch` 赋值里；
- 读取：字段名以 `.field` 形式被读。

用法：python3 scripts/check_settings_ui.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
INFRA = {'service/settings/SettingsTypes.ets', 'service/settings/SettingsStorage.ets',
         'service/settings/SettingsWriters.ets', 'service/SettingsService.ets',
         'service/StorageService.ets', 'service/settings/SettingsDefaults.ets'}


def settings_fields() -> list:
    types = (ROOT / 'service/settings/SettingsTypes.ets').read_text()
    block = re.search(r'export interface AppSettings \{(.*?)\n\}', types, re.S)
    if not block:
        return []
    return re.findall(r'^\s{2}([A-Za-z_][\w]*)\??:', block.group(1), re.M)


def ui_texts() -> list:
    texts = []
    for p in ROOT.rglob('*.ets'):
        rel = str(p.relative_to(ROOT))
        if rel in INFRA:
            continue
        texts.append(p.read_text())
    return texts


def main() -> int:
    fields = settings_fields()
    texts = ui_texts()
    no_write = []
    no_read = []
    for field in fields:
        wrote = any(re.search(r'\b' + field + r'\s*[:=]', t) for t in texts)
        read = any(re.search(r'\.' + field + r'\b', t) for t in texts)
        if not wrote:
            no_write.append(field)
        if not read:
            no_read.append(field)
    for field in no_write:
        print(f'{field}: 没有任何 UI 入口写入（设置页/播放页菜单都改不到）')
    for field in no_read:
        print(f'{field}: 没有任何地方读取（开关拨了也不生效）')
    print('total', len(no_write) + len(no_read))
    return 1 if (no_write or no_read) else 0


if __name__ == '__main__':
    sys.exit(main())
