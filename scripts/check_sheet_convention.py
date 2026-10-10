#!/usr/bin/env python3
"""面板（弹框）形态一致性检查

踩过的坑：新加功能时很自然地手写一段
    Stack { 全屏遮罩 + 居中卡片 Column().width('86%').borderRadius(20) }
看起来「能用」，但和项目其它面板完全不是一套：
- 挂在 Scroll / 页面 Column 里会被容器裁剪（设置页点选项没反应就是这么来的）；
- 遮罩只盖住页面可视区，盖不到顶部栏；
- 居中卡片是系统对话框的观感，与「底部面板 + 左标题 + 右上角 ×」的既有约定两样。

约定：所有面板一律用 components/ui/BottomSheet（系统 bindSheet）+ SheetHeader。
因此这里钉两条：
1. 全项目只有 BottomSheet 自己（以及首次启动的全屏协议拦截）可以画 maskColor 遮罩；
2. 名字以 Sheet 结尾的面板文件必须真的用到 BottomSheet。

用法：python3 scripts/check_sheet_convention.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 允许自绘遮罩：面板套件自身 + 首次启动协议拦截（系统级全屏，不是页面内面板）
MASK_ALLOWED = {
    'components/ui/BottomSheet.ets',
    'pages/NavIndex.ets',
    'theme/DesignTokens.ets',
}
MASK_PATTERN = 'maskColor()'


def main() -> int:
    problems = []
    sheets = []
    for path in sorted(ROOT.rglob('*.ets')):
        rel = str(path.relative_to(ROOT))
        text = path.read_text()
        if MASK_PATTERN in text and rel not in MASK_ALLOWED:
            problems.append(
                f'{rel}: 自绘了遮罩（{MASK_PATTERN}）—— 面板请改用 components/ui/BottomSheet')
        if path.name.endswith('Sheet.ets'):
            sheets.append(rel)
            if 'BottomSheet' not in text:
                problems.append(f'{rel}: 面板没有使用 components/ui/BottomSheet')

    print(f'面板文件 {len(sheets)} 个；自绘遮罩白名单 {len(MASK_ALLOWED)} 个')
    if problems:
        print('FAIL 面板形态不统一:')
        for p in problems:
            print(' ', p)
        return 1
    print('面板形态一致性检查通过')
    return 0


if __name__ == '__main__':
    sys.exit(main())
