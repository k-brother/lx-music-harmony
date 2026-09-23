#!/usr/bin/env python3
"""2in1 键盘操作覆盖检查

鸿蒙的 2in1（PC / 平板接键盘）是「一次开发多端部署」的一部分：
列表行、卡片这些自定义可点区域默认不可聚焦，接上键盘就只能看着。
约定是给它们加 `.focusable(true)` + `.onKeyEvent(...)`，判定逻辑统一用
utils/KeyboardTools 的 `isConfirmKey`（回车 / 小键盘回车 / 空格）。

这里只钉住「共享的行/卡片组件」——它们覆盖了绝大部分列表内容；
按钮类（Button / Text 动作项）由系统自带键盘激活，不需要处理。

用法：python3 scripts/check_keyboard.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
TARGETS = {
    'components/ui/ListRow.ets': '统一列表行',
    'components/common/LyricView.ets': '歌词行',
    'pages/LocalMusic/TrackRow.ets': '本地音乐行',
    'pages/BoardDetail/BoardSongRow.ets': '榜单/歌单歌曲行',
    'pages/Download/DownloadTaskRow.ets': '下载任务行',
    'pages/Home/SongList/SongListCard.ets': '歌单卡片',
}


def main() -> int:
    findings = []
    for rel, label in TARGETS.items():
        p = ROOT / rel
        if not p.exists():
            findings.append(f'{rel}（{label}）: 文件不存在')
            continue
        text = p.read_text()
        if '.focusable(true)' not in text:
            findings.append(f'{rel}（{label}）: 缺少 .focusable(true)，键盘无法聚焦')
        if 'isConfirmKey(' not in text:
            findings.append(f'{rel}（{label}）: 缺少回车/空格激活（isConfirmKey）')
    print('\n'.join(findings) if findings else 'all row/card components support keyboard activation')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
