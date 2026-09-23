#!/usr/bin/env python3
"""资源引用检查

三类「定义了但没人用」的资源会白白进包、也让人误以为某能力还在：
1. `resources/base/media/*` 图片；
2. `resources/base/element/string.json` 字符串（权限说明、应用名等，由
   module.json5 / app.json5 / 代码引用）；
3. `resources/rawfile/*` 原始资源（脚本、数据）。

判定：文件名/资源名在全工程（ets + json5 + 资源 json）里找不到引用即报告。
注意 `$media:layered_image` 这类间接引用会在 layered_image.json 里出现，天然被覆盖。

用法：python3 scripts/check_resources.py
"""
import json
import pathlib
import re
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent
MAIN = PROJECT / 'entry/src/main'
ROOT_FILES = [MAIN / 'module.json5', PROJECT / 'AppScope/app.json5']


def all_reference_text():
    chunks = []
    for f in ROOT_FILES:
        if f.exists():
            chunks.append(f.read_text())
    for p in MAIN.rglob('*.ets'):
        chunks.append(p.read_text())
    for p in MAIN.rglob('*.json'):
        chunks.append(p.read_text())
    return '\n'.join(chunks)


def main():
    refs = all_reference_text()
    problems = []

    media_dir = MAIN / 'resources/base/media'
    if media_dir.exists():
        for f in sorted(media_dir.iterdir()):
            if not f.is_file():
                continue
            if f.stem not in refs:
                problems.append(f'未被引用的图片资源: {f.relative_to(MAIN)}')

    string_json = MAIN / 'resources/base/element/string.json'
    if string_json.exists():
        for item in json.loads(string_json.read_text()).get('string', []):
            name = item['name']
            if f'string:{name}' not in refs and f"'{name}'" not in refs:
                problems.append(f'未被引用的字符串资源: {name}')

    raw_dir = MAIN / 'resources/rawfile'
    if raw_dir.exists():
        for f in sorted(raw_dir.rglob('*')):
            if f.is_file() and f.name not in refs:
                problems.append(f'未被引用的 rawfile: {f.relative_to(MAIN)}')

    print('\n'.join(problems) if problems else 'no unused resources')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
