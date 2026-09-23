#!/usr/bin/env python3
"""一多（响应式）覆盖检查

鸿蒙的「一次开发多端部署」是被重点审视的一项：同一套页面在手机与平板/PC 上都要
像样。我们的约定是——页面级内容列要么按断点换结构（`Breakpoints.isWide`），
要么至少把内容列居中（`Breakpoints.contentInset`）。

此前「关于」「自定义源」两个页面就是漏网的：在平板上整屏拉满，读起来很散。

不检查的页面（按设计不参与内容列居中）：
- Index / NavIndex：导航容器；
- DesktopLyricPage：独立的系统桌面歌词窗口，本身就是全屏透明层；
- PlayDetailPage：播放页用 isWide 切双栏/单栏，不算内容列。

用法：python3 scripts/check_responsive.py
"""
import pathlib
import sys

PAGES = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets/pages'
SKIP = {'Index.ets', 'NavIndex.ets', 'DesktopLyricPage.ets', 'PlayDetailPage.ets'}
TOKENS = ('Breakpoints.contentInset', 'Breakpoints.isWide', 'Breakpoints.isLarge')


def main() -> int:
    missing = []
    for p in sorted(PAGES.glob('*.ets')):
        if p.name in SKIP:
            continue
        text = p.read_text()
        if not any(token in text for token in TOKENS):
            missing.append(p.name)
    for name in missing:
        print(f'{name}: 未做一多适配（既没有 contentInset 也没有 isWide 断点分支）')
    print('total', len(missing))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
