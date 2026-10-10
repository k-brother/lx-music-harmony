#!/usr/bin/env python3
"""入口可达性检查：找出没有任何引用路径能到达的 .ets 文件。

从入口出发（Ability + 所有带 @Entry 的页面 + `setUIContent('pages/X')`
这类按名字加载的页面），沿着 import 边遍历；目录式 import
（`from '../core/network/http'`）按 `index.ets` 解析。

不可达文件要么是历史遗留（RN 目录镜像），要么是忘了接线的能力 ——
两种情况都值得处理，所以这里直接报告。

用法：python3 scripts/check_reachable.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 按设计不走 import 引用：module.json5 里注册的扩展能力
ALLOWED = ['app/entrybackupability/EntryBackupAbility.ets']

IMPORT = re.compile(r"from\s*'([^']+)'")


def resolve(spec, base):
    if not spec.startswith('.'):
        return None
    target = (base / spec).resolve()
    candidates = [pathlib.Path(str(target) + '.ets'), target / 'index.ets', target]
    for c in candidates:
        if c.exists() and c.is_file() and str(c).endswith('.ets'):
            return c.resolve()
    return None


def main():
    root = ROOT.resolve()
    files = {p.resolve(): p for p in root.rglob('*.ets')}
    texts = {p: p.read_text() for p in files.keys()}

    edges = {}
    for p, t in texts.items():
        outs = set()
        for m in IMPORT.finditer(t):
            r = resolve(m.group(1), p.parent)
            if r is not None:
                outs.add(r)
        edges[p] = outs

    all_text = '\n'.join(texts.values())
    starts = set()
    for p in files:
        if 'EntryAbility' in p.name:
            starts.add(p)
    # module.json5 注册的扩展能力（form 等）：按 srcEntry 作为入口
    module_cfg = root.parent / 'module.json5'
    if module_cfg.exists():
        for m in re.finditer(r'"srcEntry"\s*:\s*"\./ets/([^"]+)"', module_cfg.read_text()):
            cand = (root / m.group(1)).resolve()
            if cand.exists():
                starts.add(cand)
    for p, t in texts.items():
        if '@Entry' in t:
            starts.add(p)
    for m in re.finditer(r"['\"]pages/([A-Za-z0-9_]+)['\"]", all_text):
        cand = (root / 'pages' / (m.group(1) + '.ets')).resolve()
        if cand.exists():
            starts.add(cand)

    seen = set()
    stack = list(starts)
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        for nxt in edges.get(cur, ()):
            if nxt not in seen:
                stack.append(nxt)

    unreachable = []
    for p in files:
        rel = str(p.relative_to(root))
        if p not in seen and rel not in ALLOWED:
            unreachable.append(rel)
    unreachable.sort()
    print('\n'.join(unreachable) if unreachable else 'no unreachable files')
    print('total', len(unreachable))
    return 1 if unreachable else 0


if __name__ == '__main__':
    sys.exit(main())
