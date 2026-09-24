#!/usr/bin/env python3
"""开源仓库防线：提交内容里不允许出现签名口令、证书私钥、令牌、个人绝对路径。

检查的是 **git 索引里的内容**（也就是"这次提交会写进历史的东西"），不是工作区文件：
本地可以通过 `build-profile.json5` + `git update-index --skip-worktree` 保留自己的签名配置，
那份改动不会进索引，所以本检查不会误报；但只要有人真把它提交进去，这里就会拦下来。

覆盖的规则：
1. `storePassword` / `keyPassword` 等字段出现非占位值（DevEco 会把口令明文写进 build-profile.json5）；
2. 私钥文件内容（-----BEGIN ... PRIVATE KEY-----）；
3. GitHub / OpenAI 之类的令牌（ghp_ / github_pat_ / gho_ / ghs_ / sk-）；
4. 个人绝对路径 /Users/<用户名>/（会泄露本机账号名）；
5. 直接入库的签名材料文件（.p12 / .p7b / .cer / .jks / .keystore / .pem / .key）。

用法：python3 scripts/check_no_secrets.py
"""
import pathlib
import re
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent

# 占位值白名单：模板里写这些是允许的
PLACEHOLDER = re.compile(r'^\s*(|<\s*[^>]*>|\$\{[^}]*\}|REPLACE[_-]?ME|YOUR[_-]?\w*|TODO|xxx+)\s*$', re.I)

PASSWORD_FIELD = re.compile(r'"(storePassword|keyPassword|keyPasswd|password)"\s*:\s*"([^"]*)"')
PRIVATE_KEY = re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')
TOKEN = re.compile(r'\b(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|'
                   r'ghs_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})\b')
# 个人绝对路径：/Users/<用户名>/。文档里的示例路径（currentUser、yourName…）不算
PERSONAL_PATH = re.compile(r'/Users/(?!(?:currentUser|yourName|yourname|username|user|example)\b)'
                           r'[A-Za-z0-9._-]+/')
SECRET_FILE = re.compile(r'\.(p12|p7b|cer|jks|keystore|pem|key)$', re.I)

# 二进制/压缩文件不做文本扫描（只做文件名规则）
SKIP_TEXT_SUFFIX = ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.so', '.har', '.hap',
                    '.ttf', '.otf', '.zip', '.gz', '.jar', '.mp3', '.mp4')


def git(*args: str) -> str:
    return subprocess.run(['git', *args], cwd=PROJECT, capture_output=True, text=True).stdout


def main() -> int:
    tracked = git('ls-files', '-z').split('\0')
    tracked = [p for p in tracked if p]
    if not tracked:
        print('未在 git 仓库中，跳过敏感信息检查')
        return 0

    problems = []
    checked = 0
    for path in tracked:
        if SECRET_FILE.search(path):
            problems.append(f'{path}: 签名材料/私钥文件不应入库')
            continue
        if path.lower().endswith(SKIP_TEXT_SUFFIX):
            continue
        blob = subprocess.run(['git', 'show', f':{path}'], cwd=PROJECT,
                              capture_output=True, text=True, errors='replace')
        if blob.returncode != 0:
            continue
        text = blob.stdout
        checked += 1
        for lineno, line in enumerate(text.split('\n'), start=1):
            field = PASSWORD_FIELD.search(line)
            if field and not PLACEHOLDER.match(field.group(2)):
                problems.append(f'{path}:{lineno} 口令字段 {field.group(1)} 是明文，请留空或写占位值')
            if PRIVATE_KEY.search(line):
                problems.append(f'{path}:{lineno} 出现私钥内容')
            token = TOKEN.search(line)
            if token:
                problems.append(f'{path}:{lineno} 出现疑似令牌：{token.group(1)[:8]}…')
            personal = PERSONAL_PATH.search(line)
            if personal:
                problems.append(f'{path}:{lineno} 出现个人绝对路径 {personal.group(0)}')

    if problems:
        print('FAIL 提交内容里含敏感信息（开源前必须清掉）:')
        print('\n'.join(problems))
        return 1
    print(f'敏感信息检查通过（扫描 {checked} 个文本文件，无口令/私钥/令牌/个人路径）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
