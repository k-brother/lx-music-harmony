#!/usr/bin/env python3
"""词条占位符检查

三类只在真机上才会暴露、编译期不报错的问题：
1. 中英占位符不一致（英文缺失 {0} 会原样显示，或多出占位符）；
2. 含 {0} 的词条被 t() 调用（应使用 tf()，否则界面直接显示 "{0}"）；
3. tf(key, [...]) 的实参个数与占位符个数不匹配（少传一个就显示 "{1}"）。

用法：python3 scripts/check_i18n_placeholders.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'


def load(path):
    return dict(re.findall(r"m\.set\('([^']+)',\s*'([^']*)'\)", path.read_text()))


def holes(text):
    return sorted(set(re.findall(r'\{(\d+)\}', text)))


def count_args(text, open_bracket):
    """数出数组字面量里的顶层元素个数（忽略嵌套括号与字符串）"""
    depth = 0
    args = 1
    in_str = None
    j = open_bracket
    while j < len(text):
        ch = text[j]
        if in_str:
            if ch == in_str:
                in_str = None
        elif ch in '\'"`':
            in_str = ch
        elif ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
            if depth == 0:
                return 0 if j == open_bracket + 1 else args
        elif ch == ',' and depth == 1:
            args += 1
        j += 1
    return None


def main():
    zh = load(ROOT / 'service/localization/ZhCN.ets')
    en = load(ROOT / 'service/localization/EnUS.ets')
    all_text = '\n'.join(p.read_text() for p in ROOT.rglob('*.ets'))

    problems = []

    for key, value in zh.items():
        if key in en and holes(value) != holes(en[key]):
            problems.append(f'中英占位符不一致: {key} zh={holes(value)} en={holes(en[key])}')

    for key, value in zh.items():
        if holes(value) and re.search(r"\bt\('" + re.escape(key) + r"'\)", all_text):
            problems.append(f'含占位符却用 t() 调用（会显示 {value}）: {key}')

    for p in sorted(ROOT.rglob('*.ets')):
        text = p.read_text()
        for m in re.finditer(r"\btf\('([^']+)',\s*\[", text):
            key = m.group(1)
            if key not in zh:
                continue
            expect = len(holes(zh[key]))
            if expect == 0:
                continue
            got = count_args(text, m.end() - 1)
            if got is not None and got != expect:
                problems.append(f'{p.relative_to(ROOT)}: tf({key}) 传入 {got} 个参数，应为 {expect} 个')

    print('\n'.join(problems) if problems else 'no i18n placeholder problems')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
