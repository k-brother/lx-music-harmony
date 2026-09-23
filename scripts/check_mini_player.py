#!/usr/bin/env python3
"""迷你播放条覆盖检查

主流音乐 App 的每个内容页底部都有迷你播放条：用户在任何页面都能确认“正在播什么”、
一键回播放页。此前只有首页/本地音乐/歌单详情/榜单详情有，历史、我喜欢、我的歌单、
下载、评论五个页面缺，切回来还要先回首页，属于一眼可见的不一致。

判定：`pages/` 下的内容页必须挂载 `PlayerBar`。以下页面按设计不挂：
- Index / NavIndex：导航容器，不含内容；
- PlayDetailPage：全屏播放页，本身是播放控制；
- DesktopLyricPage：独立桌面歌词窗口；
- LogPage：诊断页，不属于内容浏览路径；
- DownloadPage：它是首页「下载管理」Tab 的内容，迷你条由外层 HomePage/MainPane 提供
  （自己再挂一条会出现上下两条迷你条，真机截图已确认过）。

用法：python3 scripts/check_mini_player.py
"""
import pathlib
import sys

PAGES = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets/pages'
SKIP = {'Index.ets', 'NavIndex.ets', 'PlayDetailPage.ets', 'DesktopLyricPage.ets', 'LogPage.ets',
        'DownloadPage.ets'}


def main() -> int:
    missing = []
    for p in sorted(PAGES.glob('*.ets')):
        if p.name in SKIP:
            continue
        if 'PlayerBar(' not in p.read_text():
            missing.append(p.name)
    for name in missing:
        print(f'{name}: 未挂载迷你播放条 PlayerBar')
    print('total', len(missing))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
