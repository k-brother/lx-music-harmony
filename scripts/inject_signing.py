#!/usr/bin/env python3
"""把本机的签名配置注入 build-profile.json5，结果写到 stdout。

仓库里的 `build-profile.json5` 是脱敏版（`signingConfigs` 为空），证书与口令一律不入库；
需要签名构建时（本地或 CI）这样用：

    python3 scripts/inject_signing.py --signing-dir ~/my-signing > build-profile.json5

规则：

1. 读 `<signing-dir>/build-profile.local.json5`（也可以用 `--config` 指定别处）；
2. `storeFile` / `profile` / `certpath` 三个字段若是**相对路径**，一律按
   `<signing-dir>/<文件名>` 解析成绝对路径 —— 证书/密钥集中放一个目录，最省事的约定；
3. 已经是绝对路径的字段原样保留（例如 DevEco 自动生成的调试签名指向 `~/.ohos/config`）。

这样 CI 里不需要假设任何本地目录结构，也就不用往仓库里写私有路径。
注意：输出内容含签名口令，只应写进工作区供构建使用，不要提交。
"""
import argparse
import os
import pathlib
import re
import sys

PATH_KEYS = ('storeFile', 'profile', 'certpath')
KEY_PATTERN = re.compile(r'("(?:%s)"\s*:\s*")([^"]*)(")' % '|'.join(PATH_KEYS))
WINDOWS_ABS = re.compile(r'^[A-Za-z]:[\\/]')


def resolve(value: str, signing_dir: str) -> str:
    if not value or value.startswith('/') or WINDOWS_ABS.match(value):
        return value
    return os.path.join(signing_dir, os.path.basename(value))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--signing-dir', required=True,
                        help='签名材料目录（证书/密钥与 build-profile.local.json5 所在处）')
    parser.add_argument('--config', default='',
                        help='默认 <signing-dir>/build-profile.local.json5')
    args = parser.parse_args()

    signing_dir = os.path.abspath(os.path.expanduser(args.signing_dir))
    config = pathlib.Path(args.config or os.path.join(signing_dir, 'build-profile.local.json5'))
    if not config.is_file():
        print(f'FAIL 找不到签名配置 {config}', file=sys.stderr)
        return 1

    text = config.read_text(encoding='utf-8')
    rewritten = KEY_PATTERN.sub(
        lambda m: f'{m.group(1)}{resolve(m.group(2), signing_dir)}{m.group(3)}', text)

    missing = [name for name in PATH_KEYS
               if f'"{name}"' in rewritten]
    if not missing:
        print('FAIL 配置里没有 storeFile / profile / certpath，像是空配置', file=sys.stderr)
        return 1

    for name in PATH_KEYS:
        for value in re.findall(rf'"{name}"\s*:\s*"([^"]*)"', rewritten):
            if value and not (value.startswith('/') or WINDOWS_ABS.match(value)):
                print(f'FAIL {name} 仍是相对路径：{value}', file=sys.stderr)
                return 1

    sys.stdout.write(rewritten)
    return 0


if __name__ == '__main__':
    sys.exit(main())
