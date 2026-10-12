#!/usr/bin/env python3
"""@Builder 传状态字段检查

ArkUI V1 里 @Builder 的参数不参与状态依赖追踪：把会变的状态（@State/@Prop/
@StorageProp…）当参数传进去，某些场景下参数变化不会重新渲染（本工程先后踩过
「播放模式文案不更新」「输入框内容不刷新」等几次）。

**同一个坑还有另一个方向**（真机踩过，见 `HomeBottomDock` 的文件头注释）：
带参数的 @Builder 会被 ArkUI **按参数缓存** —— 只有状态变化、参数没变时它不会重建，
于是"在它内部直接读 this.xxx"同样拿不到新值。设置页底舱就是这样：迷你条已按 `compact`
收拢了，同一个 Builder 里的 Tab 栏却没拿到 `collapsed`，停在展开态。

约定：会变的内容用 @Component + @Prop（组件之间靠 @Prop 传值，更新链路可靠）；
@Builder 要么不带参数，要么只做"参数决定内容"的纯展示。

两条判定（都不误伤"item 型"Builder —— 它们的实参来自数据，数据变了参数就变，会正常重建）：
1. 调用点把 `this.<状态字段>` 当参数传进带参数的 @Builder；
2. **调用点用常量实参调用带参数的 @Builder，而该 Builder 内部又读 `this.<状态字段>`**
   —— 参数永远是同一个常量，状态变化时它不会被重建，里面读到的状态就是旧的。

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


def builder_body(text, from_index):
    """返回 while 起始处（@Builder 签名之后）到方法体结束之间的文本"""
    brace = text.find('{', from_index)
    if brace < 0:
        return ''
    depth = 0
    i = brace
    while i < len(text):
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return text[brace:i]
        i += 1
    return text[brace:]


def main():
    problems = []
    notes = []
    for p in sorted(ROOT.rglob('*.ets')):
        text = p.read_text()
        states = set(m.group(2) for m in STATE.finditer(text))
        if not states:
            continue
        builders = {}
        constant_calls = set()
        for m in BUILDER.finditer(text):
            params = [x.strip().split(':')[0].strip() for x in m.group(2).split(',') if x.strip()]
            builders[m.group(1)] = params
        # 收集"用字面量实参调用"的 Builder：参数永远是同一个常量 → 内部读状态一定是旧值。
        # 只认真正的字面量（true/false/数字/字符串）：循环变量、局部变量、t(...) 这类
        # 实参会随数据变化，Builder 会正常重建，不算问题（否则会误伤一大批 item 型 Builder）。
        LITERAL = re.compile(r"^(?:true|false|-?\d+(?:\.\d+)?|'[^']*')$")
        for name, params in builders.items():
            if not params:
                continue
            for m in re.finditer(r'this\.' + re.escape(name) + r'\(', text):
                args, _ = call_args(text, m.end() - 1)
                parts = [a.strip() for a in args.split(',') if a.strip()]
                if parts and all(LITERAL.match(a) for a in parts):
                    constant_calls.add(name)
        for name in sorted(constant_calls):
            for m in BUILDER.finditer(text):
                if m.group(1) != name:
                    continue
                body = builder_body(text, m.end())
                hits = sorted(set(re.findall(r'this\.([A-Za-z_$][\w$]*)', body)) & states)
                if hits:
                    line = text[:m.start()].count('\n') + 1
                    # 只提示不拦：这类写法多数在真机上也能刷新（Builder 的重建策略与版本相关），
                    # 但"状态驱动的 UI"用 @Component + @Prop 才是可靠链路，值得逐个收敛。
                    notes.append(
                        f'{p.relative_to(ROOT)}:{line} @Builder {name} 被字面量实参调用、内部却读了状态 {hits}'
                        '（建议拆成 @Component + @Prop）')
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
    if notes:
        print(f'NOTE 待收敛的 @Builder（{len(notes)} 处，不阻塞）：')
        print('\n'.join('  ' + n for n in notes))
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
