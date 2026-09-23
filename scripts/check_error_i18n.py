#!/usr/bin/env python3
"""错误文案多语言检查

逻辑层（core/ service/）里硬编码的中文错误信息有两个问题：
1. 它们经常直接被展示（下载任务的失败原因、状态面板的提示），英文界面下会出现中文；
2. 无法随语言切换。

本轮就是这样发现下载失败原因写死了「文件保存失败」。

判定：core/ 与 service/ 下不允许
- `throw new Error('<含中文>')`；
- 形如 `xxxError = '<含中文>'` / `xxxMsg = '<含中文>'` 的字面量赋值。

数据文件（榜单名、标签名、主题名、歌词、协议、默认歌单名等）按设计就是中文数据，跳过。

用法：python3 scripts/check_error_i18n.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
SKIP_PREFIXES = (
    'core/theme/data/', 'core/legal/', 'core/lyric/S2TTable.ets',
    'core/music/sources/kw/leaderboard', 'core/music/sources/kg/leaderboard',
    'core/music/sources/tx/leaderboard', 'core/music/sources/wy/leaderboard',
    'core/music/sources/mg/leaderboard', 'core/music/sources/kw/songList',
    'core/music/sources/kg/songList', 'core/music/sources/tx/songList',
    'core/music/sources/wy/songList', 'core/music/sources/mg/songList',
    'core/music/sources/kw/hotSearch', 'core/music/sources/kg/hotSearch',
    'core/music/sources/tx/hotSearch', 'core/music/sources/wy/hotSearch',
    'core/music/sources/mg/hotSearch', 'service/backup/BackupDataMapping.ets',
    'service/list/ListStorage.ets', 'service/sync/SyncDataMapper.ets',
)
THROW = re.compile(r"throw new Error\('([^']*[\u4e00-\u9fff][^']*)'")
# 变量名可能是 msg / error 本身，也可能是 xxxMsg / xxxError（两种写法都要覆盖，
# 只匹配「以 Msg 结尾」会漏掉 `let msg = '文件保存失败';` 这种最常见的写法）
ASSIGN = re.compile(
    r"(?:\b(?:msg|message|error|err)\b|[A-Za-z_][\w]*(?:[Mm]sg|[Ee]rror|[Mm]essage))\s*=\s*'([^']*[\u4e00-\u9fff][^']*)'")


def main() -> int:
    findings = []
    for p in sorted(ROOT.rglob('*.ets')):
        rel = str(p.relative_to(ROOT))
        if not (rel.startswith('core/') or rel.startswith('service/')):
            continue
        if rel.startswith(SKIP_PREFIXES):
            continue
        for i, line in enumerate(p.read_text().split('\n'), start=1):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue
            m = THROW.search(line)
            if m:
                findings.append(f'{rel}:{i} 硬编码中文错误文案「{m.group(1)}」（应走 i18n）')
                continue
            m = ASSIGN.search(line)
            if m:
                findings.append(f'{rel}:{i} 硬编码中文错误文案「{m.group(1)}」（应走 i18n）')
    print('\n'.join(findings) if findings else 'no hardcoded chinese error text in logic layer')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
