#!/usr/bin/env python3
"""在线内容页「失败态」检查

拉数据失败时如果只把列表清空，页面会显示「暂无数据」——用户以为这个榜单/搜索结果
真的没内容，只能退出去再进来。商业化 App 的写法是：失败 = 明确文案 + 一键重试。

此前只有歌单详情做了失败态，榜单详情 / 排行榜 / 歌单广场 / 评论都混在空态里。

判定：这些联网页必须同时具备
- 失败标记（hasError）
- 失败态渲染（state: 'error'）
- 重试入口（actionText: t('retry')）

用法：python3 scripts/check_error_states.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
ONLINE_PAGES = {
    'pages/SonglistDetailPage.ets': '歌单详情',
    'pages/BoardDetailPage.ets': '榜单详情',
    'pages/Home/LeaderboardView.ets': '排行榜',
    'pages/Home/SongListView.ets': '歌单广场',
    'pages/CommentPage.ets': '评论',
}


def main() -> int:
    findings = []
    for rel, label in ONLINE_PAGES.items():
        path = ROOT / rel
        if not path.exists():
            findings.append(f'{rel}（{label}）: 文件不存在')
            continue
        text = path.read_text()
        if 'hasError' not in text:
            findings.append(f'{rel}（{label}）: 没有失败标记（失败会被当成空态）')
        if "state: 'error'" not in text:
            findings.append(f'{rel}（{label}）: 没有失败态渲染')
        if "actionText: t('retry')" not in text:
            findings.append(f'{rel}（{label}）: 失败态没有重试入口')
    print('\n'.join(findings) if findings else 'all online pages distinguish failure from empty')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
