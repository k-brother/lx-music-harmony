#!/usr/bin/env python3
"""设置项「有入口 / 有人读」检查

两类很隐蔽的功能缺失：
1. 设置项没有 UI 入口 —— 字段存在、落盘也有，但用户永远改不到
   （本轮前面的逐字歌词就是这样：先加了字段，入口还没接上）；
2. 设置项没人读 —— 开关拨来拨去，播放/列表侧根本不看它。

判定：
- 写入：只认设置界面目录里的 `update({ field: ... })` 字面量，或任意文件里的 `patch.field = ...`；
  刻意不采用「任何地方出现过同名标识符」——`getPlayQuality(highQuality)` 这种无关的同名参数
  会让检查形同虚设（它确实骗过一次）；
- 读取：字段名以 `.field` 形式在非基础设施文件里被读。
只用于迁移旧版本、没有界面的字段显式列进 LEGACY。

用法：python3 scripts/check_settings_ui.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
INFRA = {'service/settings/SettingsTypes.ets', 'service/settings/SettingsStorage.ets',
         'service/settings/SettingsWriters.ets', 'service/SettingsService.ets',
         'service/StorageService.ets', 'service/settings/SettingsDefaults.ets'}
# 只做旧版本迁移、不需要界面的字段（存储键仍在 StorageService）
LEGACY = {'highQuality'}
# 把 patch 转交给 settingsService.update 的包装函数（桌面歌词外观改动走它统一重算窗口）
WRITE_WRAPPERS = ('persistAppearance',)


def settings_fields() -> list:
    types = (ROOT / 'service/settings/SettingsTypes.ets').read_text()
    block = re.search(r'export interface AppSettings \{(.*?)\n\}', types, re.S)
    if not block:
        return []
    return re.findall(r'^\s{2}([A-Za-z_][\w]*)\??:', block.group(1), re.M)


def scan() -> tuple:
    """返回 (全部非基础设施文件文本, 写入过的字段集合)

    写入集合只包含两类可信证据：
    - `settingsService.update({ field: ... })` 字面量里出现的字段；
    - `patch.field = ...` 形式的分段赋值。
    这样 `getPlayQuality(highQuality)` 之类的同名参数不会被误当成入口。
    """
    texts = []
    written = set()
    call_exp = r'\.update\(\{([^}]*)\}'
    for wrapper in WRITE_WRAPPERS:
        call_exp += r'|' + wrapper + r'\(\{([^}]*)\}'
    for p in ROOT.rglob('*.ets'):
        rel = str(p.relative_to(ROOT))
        if rel in INFRA:
            continue
        text = p.read_text()
        texts.append(text)
        for call in re.finditer(call_exp, text, re.S):
            body = call.group(1) if call.group(1) is not None else call.group(2)
            written.update(re.findall(r'([A-Za-z_][\w]*)\s*:', body))
            # 简写形式 `{ themeId }`
            written.update(re.findall(r'(?:^|[,{])\s*([A-Za-z_][\w]*)\s*(?=[,}])', body))
        for m in re.finditer(r'\b(patch|next|draft|values)\.([A-Za-z_][\w]*)\s*=(?!=)', text):
            written.add(m.group(2))
    return texts, written


def main() -> int:
    fields = settings_fields()
    texts, written = scan()
    no_write = []
    no_read = []
    for field in fields:
        wrote = field in LEGACY or field in written
        read = field in LEGACY or any(
            re.search(r'\.' + field + r'\b', t) or re.search(r"'(%s)'" % field, t) for t in texts)
        if not wrote:
            no_write.append(field)
        if not read:
            no_read.append(field)
    for field in no_write:
        print(f'{field}: 没有任何 UI 入口写入（设置页/播放页菜单都改不到；只做迁移请加进 LEGACY）')
    for field in no_read:
        print(f'{field}: 没有任何地方读取（开关拨了也不生效）')
    print('total', len(no_write) + len(no_read))
    return 1 if (no_write or no_read) else 0


if __name__ == '__main__':
    sys.exit(main())
