#!/usr/bin/env python3
"""找出「函数体完全相同」的重复实现。

做法：按大括号配对切出每个函数体，把数字字面量归一化后取 MD5，
同哈希且出现在 2 个以上文件时报告 —— 这是可以安全收敛的对象。
（同一文件内同名重载会跳过，避免误报。）

用法：python3 scripts/check_duplicate_impls.py [--all]
  默认只报告跨文件的重复实现（收敛候选）；
  --all 额外报告同文件内的重复实现。
"""
import hashlib
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 函数签名：可选修饰符 + 名字 + 参数列表（后面必须跟 { 或 : 返回类型 {）
SIG = re.compile(
    r'^\s*(?:(?:export|private|public|protected|static|async|declare)\s+)*'
    r'([A-Za-z_$][\w$]*)\s*\(([^;{]*)\)\s*(?::\s*[^{;]+?)?\s*\{\s*$'
)

SKIP_NAMES = {'if', 'for', 'while', 'switch', 'catch', 'constructor', 'get', 'set'}


def normalize(body: str) -> str:
    body = re.sub(r'//.*', '', body)
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    body = re.sub(r'\d+', '0', body)
    body = re.sub(r'\s+', ' ', body)
    return body.strip()


def extract(path: pathlib.Path):
    lines = path.read_text().split('\n')
    out = []
    i = 0
    while i < len(lines):
        m = SIG.match(lines[i])
        if not m or m.group(1) in SKIP_NAMES:
            i += 1
            continue
        name = m.group(1)
        depth = 1
        j = i + 1
        body = []
        while j < len(lines) and depth > 0:
            depth += lines[j].count('{') - lines[j].count('}')
            if depth > 0:
                body.append(lines[j])
            j += 1
        text = '\n'.join(body)
        if len(body) >= 4:  # 太短的（getter 之类）不值得收敛
            out.append((name, i + 1, text))
        i = j
    return out


def main() -> int:
    show_same_file = '--all' in sys.argv
    groups: dict[str, list] = {}
    for p in sorted(ROOT.rglob('*.ets')):
        for name, line, body in extract(p):
            key = hashlib.md5(normalize(body).encode()).hexdigest()
            groups.setdefault(key, []).append((str(p.relative_to(ROOT)), line, name))

    dupes = 0
    for key, items in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        files = {it[0] for it in items}
        if len(items) < 2:
            continue
        if len(files) < 2 and not show_same_file:
            continue
        dupes += len(items) - 1
        print(f'--- 重复实现 x{len(items)}')
        for f, line, name in items:
            print(f'    {f}:{line}  {name}()')
    print('可收敛的重复实现数：', dupes)
    return 0


if __name__ == '__main__':
    sys.exit(main())
