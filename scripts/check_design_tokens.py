#!/usr/bin/env python3
"""设计系统收口检查

README 里写的是「DesignTokens 是全应用唯一的视觉出口」，这条得能被验证，
否则过一段时间又会散出裸数值与裸颜色：

1. pages/components 下不允许 `.fontSize(<数字>)`（动态表达式如
   `.fontSize(this.lyricFontSize + 4)` 不算）；
2. 不允许写死颜色字面量（#RRGGBB / #AARRGGBB / rgba(...)），
   白名单是「用户可配置 / 有意为之」的三处（见 ALLOWED）。

用法：python3 scripts/check_design_tokens.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 有意保留字面量的文件（用户可配置的默认值 / 动态渐变）
ALLOWED = {
    'pages/DesktopLyricPage.ets',            # 桌面歌词默认配色（设置里可改）
    'pages/Home/Setting/DesktopLyricSection.ets',  # 颜色预设选项本身
    'pages/PlayDetailPage.ets',              # 动态背景渐变（按主题拼半透明色）
    'pages/Home/Setting/AppearanceSection.ets',    # 主题预览色（主题数据驱动）
}

FONT = re.compile(r'\.fontSize\((\d+)\)')
COLOR = re.compile(r"'#[0-9A-Fa-f]{3,8}'|\"#[0-9A-Fa-f]{3,8}\"|'rgba?\([^)]*\)'")


def main():
    problems = []
    for folder in ('pages', 'components'):
        for p in sorted((ROOT / folder).rglob('*.ets')):
            rel = str(p.relative_to(ROOT))
            text = p.read_text()
            for m in FONT.finditer(text):
                line = text[:m.start()].count('\n') + 1
                problems.append(f'{rel}:{line} 裸字号 {m.group(0)}，请用 DesignTokens.fontXxx()')
            if rel in ALLOWED:
                continue
            for m in COLOR.finditer(text):
                line = text[:m.start()].count('\n') + 1
                problems.append(f'{rel}:{line} 写死颜色 {m.group(0)}，请用 DesignTokens')

    print('\n'.join(problems) if problems else 'design tokens 收口通过')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
