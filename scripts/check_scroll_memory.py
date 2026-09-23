#!/usr/bin/env python3
"""「记住列表滚动位置」覆盖检查

这个设置项此前只有歌单详情实现了：同样是长列表，榜单详情/历史/我喜欢/本地音乐
退出再进来都回到顶部，同一个开关在不同页面表现不一致。

判定两件事：
1. 这些长列表页面必须真的响应设置（存在 rememberScrollPosition 且用了记忆机制）；
2. 页面拿到把手后必须成对调用 restore / dispose（漏 dispose 会把回调打到已销毁的列表上）。

用法：python3 scripts/check_scroll_memory.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
# 长列表页面：设置开启时都要能回到上次位置
PAGES = {
    'pages/SonglistDetailPage.ets': '歌单详情',
    'pages/BoardDetailPage.ets': '榜单详情',
    'pages/HistoryListPage.ets': '播放历史',
    'pages/LoveListPage.ets': '我喜欢',
    'pages/LocalMusicPage.ets': '本地音乐',
}


def main() -> int:
    findings = []
    for rel, label in PAGES.items():
        path = ROOT / rel
        if not path.exists():
            findings.append(f'{rel}（{label}）: 文件不存在')
            continue
        text = path.read_text()
        if 'rememberScrollPosition' not in text:
            findings.append(f'{rel}（{label}）: 没有响应「记住滚动位置」设置')
        if 'ScrollMemoryHandle' not in text and 'loadScrollOffset' not in text:
            findings.append(f'{rel}（{label}）: 没有使用滚动位置记忆机制')
        if 'ScrollMemoryHandle' in text:
            if '.restore(' not in text:
                findings.append(f'{rel}（{label}）: 拿了 ScrollMemoryHandle 但没有 restore')
            if '.dispose(' not in text:
                findings.append(f'{rel}（{label}）: 拿了 ScrollMemoryHandle 但没有 dispose（定时器会泄漏）')
    print('\n'.join(findings) if findings else 'all long lists honour scroll memory')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
