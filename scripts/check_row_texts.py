#!/usr/bin/env python3
"""列表行文案出口检查

「歌手 · 专辑 · 音源」以前是每个页面各拼一遍，于是「设置 → 列表 → 显示专辑 / 显示音源 /
显示时长」只在歌单详情生效，其它列表照旧全显示 —— 同一开关在不同页面表现不一致。

现在拼装只剩 core/list/RowTexts.ets 一处，行组件统一调它。判定：
1. 除 RowTexts 外，不许再出现手拼的「歌手 · 专辑」副标题；
2. 行组件（ListRow / TrackRow / BoardSongRow）必须引用统一拼装；
3. 三个列表显示开关必须被行组件读取（@StorageProp）。

用法：python3 scripts/check_row_texts.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
ROW_TEXTS = 'core/list/RowTexts.ets'
ROW_COMPONENTS = {
    'components/ui/ListRow.ets': '统一列表行',
    'pages/LocalMusic/TrackRow.ets': '本地音乐行',
    'pages/BoardDetail/BoardSongRow.ets': '榜单歌曲行',
}
SETTING_KEYS = ('showListAlbum', 'showListSource', 'showListDuration')
# 手拼副标题的特征：模板串里同时出现 singer 与 album
MANUAL_SUBTITLE = re.compile(r'`\$\{[^`]*singer[^`]*\}[^`]*·[^`]*\$\{[^`]*album')


def main() -> int:
    findings = []
    row_texts = ROOT / ROW_TEXTS
    if not row_texts.exists():
        findings.append(f'{ROW_TEXTS}: 缺少统一拼装实现')
    else:
        text = row_texts.read_text()
        for name in ('composeRowSubtitle', 'composeRowDurationText'):
            if f'export function {name}' not in text:
                findings.append(f'{ROW_TEXTS}: 缺少 {name}')
    for rel, label in ROW_COMPONENTS.items():
        path = ROOT / rel
        if not path.exists():
            findings.append(f'{rel}（{label}）: 文件不存在')
            continue
        text = path.read_text()
        # 必须真的调用（只 import 不算）：判定带括号的调用形式
        if 'composeRowSubtitle(' not in text:
            findings.append(f'{rel}（{label}）: 没有真正调用统一副标题拼装')
        if 'composeRowDurationText(' not in text:
            findings.append(f'{rel}（{label}）: 没有真正调用统一时长拼装')
        for key in SETTING_KEYS:
            if key not in text:
                findings.append(f'{rel}（{label}）: 没有响应「列表显示」设置 {key}')
    for p in sorted(ROOT.rglob('*.ets')):
        rel = str(p.relative_to(ROOT))
        if rel == ROW_TEXTS:
            continue
        for i, line in enumerate(p.read_text().split('\n')):
            if MANUAL_SUBTITLE.search(line):
                findings.append(f'{rel}:{i + 1} 手拼「歌手 · 专辑」副标题（应走 RowTexts）')
    print('\n'.join(findings) if findings else 'row texts all go through RowTexts')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
