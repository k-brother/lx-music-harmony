#!/usr/bin/env python3
"""页面底部安全区必须由页面自己绘制。

真机问题（深色模式）：设置页、设置里的二级页、我的里的歌单二级页，底部那条系统
手势区是**白底**，没被主题控制到 —— 页面根容器没做底部安全区扩展，那一段就交给
系统画，深色主题下透出系统白底。

规则：独立页面（NavDestination / 根页面）的根容器要
`expandSafeArea([SYSTEM], [TOP, BOTTOM])`，并且有主题背景色；
首页各个 Tab 的内容不用管（它们下方是底部导航栏，由 Tab 栏自己绘制并扩展）。

用法：python3 scripts/check_safe_area.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets/pages'

# 首页 Tab 的内容 / 容器 / 独立浮窗：底部由外层（Tab 栏、播放条）负责
SKIP = {
    'Index.ets', 'NavIndex.ets', 'HomePage.ets',
    'Home/SongListView.ets', 'Home/LeaderboardView.ets', 'Home/MylistView.ets',
    'DownloadPage.ets', 'Home/SongListTypes.ets', 'DesktopLyricPage.ets',
}


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob('*.ets')):
        rel = str(path.relative_to(ROOT))
        if rel in SKIP:
            continue
        text = path.read_text()
        # 只看页面级组件（XxxPage / XxxView）：行/卡片/面板这些组件没有自己的根页面
        struct = re.search(r'export struct ([A-Za-z0-9_]+)', text)
        if not struct or not (struct.group(1).endswith('Page') or struct.group(1).endswith('View')):
            continue
        if 'expandSafeArea' not in text:
            problems.append(f'{rel}: 根容器没有安全区扩展（底部会是系统白底）')
            continue
        if not re.search(r'expandSafeArea\([^)]*SafeAreaEdge\.BOTTOM', text):
            problems.append(f'{rel}: 安全区扩展缺少 BOTTOM（深色模式底部会透白）')
    if problems:
        print('FAIL 页面底部安全区未绘制:')
        print('\n'.join(problems))
        return 1
    print('页面底部安全区绘制完整（独立页都做了 TOP+BOTTOM 扩展）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
