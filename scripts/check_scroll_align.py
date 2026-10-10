#!/usr/bin/env python3
"""纵向 Scroll 必须显式声明对齐方式

踩过的坑（真机截图定位的）：ArkUI 里 `Scroll` 的 `align` **默认是 `Alignment.Center`**
（SDK common.d.ts："Default value: Alignment.Center"，且 Scroll 在支持列表里）——
子内容不足一屏时整块内容会被**垂直居中**，短页面顶部与底部各留一大片空白。

设置页以前内容很长，看不出来；首页改成「分类入口」之后内容变短，一眼就露出来了
（更早的下载页踩过，所以它那里单独写过 `.align(Alignment.TopStart)`，只是没沉成约定）。

约定：纵向 Scroll 一律**显式**写 `.align(...)`：
- 列表/表单/正文页写 `Alignment.TopStart`；
- 确实需要居中的（识曲空闲态的大麦克风按钮）写 `Alignment.Center` 并注明原因。
显式写出来，读代码的人才知道是「有意为之」还是「没想过」。

横向 Scroll（`scrollable(ScrollDirection.Horizontal)`）不受影响，跳过。

用法：python3 scripts/check_scroll_align.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'


def block_end(text: str, open_brace: int) -> int:
    """返回与 open_brace 配对的右花括号下标"""
    depth = 0
    i = open_brace
    while i < len(text):
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text) - 1


def chain_after(text: str, scroll_start: int) -> str:
    """取 Scroll 代码块之后紧跟的修饰符链

    修饰符体可能跨多行（`.onDidScroll(() => { ... })`），也可能夹注释，
    所以不能按行扫描：从块结束处一路吃到「同层级的 } 或 ;」为止。
    """
    end = block_end(text, text.index('{', scroll_start))
    i = end + 1
    depth = 0
    while i < len(text):
        ch = text[i]
        if ch in '{([':
            depth += 1
        elif ch in '})]':
            if depth == 0:
                break
            depth -= 1
        elif ch == ';' and depth == 0:
            break
        elif ch == '/' and depth == 0:
            if text[i:i + 2] == '//':
                newline = text.find('\n', i)
                i = len(text) if newline < 0 else newline
                continue
            if text[i:i + 2] == '/*':
                close = text.find('*/', i)
                i = len(text) if close < 0 else close + 2
                continue
        i += 1
    return text[end + 1:i]


def main() -> int:
    problems = []
    checked = 0
    skipped_horizontal = 0
    for path in sorted(ROOT.rglob('*.ets')):
        text = path.read_text()
        rel = str(path.relative_to(ROOT))
        for match in re.finditer(r'\bScroll\(', text):
            start = match.start()
            if '{' not in text[start:start + 200]:
                continue
            chain = chain_after(text, start)
            if 'scrollable(' in chain and 'Horizontal' in chain:
                skipped_horizontal += 1
                continue
            checked += 1
            if '.align(' not in chain:
                line = text[:start].count('\n') + 1
                problems.append(f'{rel}:{line}: 纵向 Scroll 没有显式 .align(...)（默认会垂直居中，短内容上下留白）')

    print(f'纵向 Scroll {checked} 处（横向 {skipped_horizontal} 处已跳过）')
    if problems:
        print('FAIL 纵向 Scroll 未声明对齐:')
        for p in problems:
            print(' ', p)
        return 1
    print('纵向 Scroll 对齐检查通过')
    return 0


if __name__ == '__main__':
    sys.exit(main())
