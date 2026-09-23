#!/usr/bin/env python3
"""找出「导出但全项目零引用」的声明。

判定方式：把 `export function/const/class/interface/type/struct NAME` 里的名字
放回整个 ets 源码里数出现次数，只有声明那一处即为零引用。

这类声明是「有实现没入口」或纯历史遗留的典型信号，删掉它们能显著减少
「看起来有某能力、实际没人调用」的误导。注意：只有真正全项目无引用才报告，
同文件内部使用（例如仅供本文件消费的 interface）不会被误判。

用法：python3 scripts/check_unused_exports.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

DECL = re.compile(
    r'^export\s+(?:async\s+)?(?:function|const|class|interface|type|struct)\s+([A-Za-z_$][\w$]*)'
)


def main() -> int:
    files = sorted(ROOT.rglob('*.ets'))
    texts = {p: p.read_text() for p in files}
    all_text = '\n'.join(texts.values())

    report = []
    for p in files:
        for i, line in enumerate(texts[p].split('\n')):
            m = DECL.match(line)
            if not m:
                continue
            name = m.group(1)
            # 减去声明这一行自身
            if len(re.findall(r'\b' + re.escape(name) + r'\b', all_text)) - 1 <= 0:
                report.append(f'{p.relative_to(ROOT)}:{i + 1} 零引用导出: {name}')

    print('\n'.join(report) if report else 'no unused exports')
    print('total', len(report))
    return 1 if report else 0


if __name__ == '__main__':
    sys.exit(main())
