#!/usr/bin/env python3
"""@Builder 传状态字段检查

ArkUI V1 里 @Builder 的参数不参与状态依赖追踪：把会变的状态（@State/@Prop/
@StorageProp…）当参数传进去，某些场景下参数变化不会重新渲染（本工程先后踩过
「播放模式文案不更新」「输入框内容不刷新」等几次）。

约定：会变的内容用 @Component + @Prop（或在 @Builder 内部直接读 this.*）。

判定：@Builder 定义带参数，调用点实参里出现 `this.<状态字段>` 即报告。

用法：python3 scripts/check_builder_state_args.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

STATE = re.compile(
    r"@(State|Prop|StorageProp|StorageLink|Link|ObjectLink|Provide|Consume)"
    r"\s*(?:\([^)]*\))?\s+([A-Za-z_$][\w$]*)"
)
BUILDER = re.compile(r"@Builder\s*\n\s*([A-Za-z_$][\w$]*)\s*\(([^)]*)\)")


def call_args(text, open_paren):
    """返回 (实参文本, 右括号下标)"""
    depth = 0
    j = open_paren
    while j < len(text):
        ch = text[j]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return text[open_paren + 1:j], j
        j += 1
    return text[open_paren + 1:], len(text) - 1


def main():
    problems = []
    for p in sorted(ROOT.rglob('*.ets')):
        text = p.read_text()
        states = set(m.group(2) for m in STATE.finditer(text))
        if not states:
            continue
        builders = {}
        for m in BUILDER.finditer(text):
            params = [x.strip().split(':')[0].strip() for x in m.group(2).split(',') if x.strip()]
            builders[m.group(1)] = params
        for name, params in builders.items():
            if not params:
                continue
            for m in re.finditer(r'this\.' + re.escape(name) + r'\(', text):
                args, _ = call_args(text, m.end() - 1)
                hits = sorted(set(re.findall(r'this\.([A-Za-z_$][\w$]*)', args)) & states)
                if hits:
                    line = text[:m.start()].count('\n') + 1
                    problems.append(f'{p.relative_to(ROOT)}:{line} this.{name}(...) 传入状态字段 {hits}')

    print('\n'.join(problems) if problems else 'no @Builder with state args')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
