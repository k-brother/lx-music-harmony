#!/usr/bin/env python3
"""把打好的 HAP 发到 GitHub Release（不依赖 gh CLI）。

为什么单独一个脚本：工作流里用 shell + curl 拼 JSON 很容易在转义上翻车（备注里带换行、
引号就炸），而且"同名附件重复上传"必须显式处理。这里用标准库 urllib 做，跑在
self-hosted runner 上不需要装任何东西。

行为：
1. 按 tag 找 Release，没有就新建（先让 GitHub 生成「What's Changed」提交清单）；
2. 把 `--notes-file` 的内容 + 本次构建链接**前置**到 Release 正文（只在新建时写一次，
   重跑不会把说明叠加两遍）；
3. 上传附件：同名附件先删后传（重跑安全）；
4. 打印每个附件的下载地址。

用法：
  GITHUB_TOKEN=xxx python3 scripts/publish_release.py \
      --repo k-brother/lx-music-harmony --tag v1.0.0 \
      --notes-file .github/RELEASE_NOTES.md \
      --run-url https://github.com/k-brother/lx-music-harmony/actions/runs/123 \
      dist/*.hap
"""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

API = 'https://api.github.com'
UPLOADS = 'https://uploads.github.com'
USER_AGENT = 'lx-music-harmony-release'


def call(url: str, token: str, method: str = 'GET', payload=None,
         content_type: str = 'application/json', allow_404: bool = False):
    data = None
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': USER_AGENT,
        'X-GitHub-Api-Version': '2022-11-28',
    }
    if payload is not None:
        if isinstance(payload, bytes):
            data = payload
        else:
            data = json.dumps(payload).encode('utf-8')
        headers['Content-Type'] = content_type
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf-8', 'replace')
        if error.code == 404 and allow_404:
            return None
        print(f'FAIL {method} {url} -> HTTP {error.code}\n{detail}', file=sys.stderr)
        sys.exit(1)


def build_body(notes: str, run_url: str, generated: str) -> str:
    parts = [notes.strip()]
    if run_url:
        parts.append(f'> 本次构建由 GitHub Actions 自动完成，日志见 {run_url}')
    if generated.strip():
        parts.append(generated.strip())
    return '\n\n'.join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True, help='owner/name')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--notes-file', default='')
    parser.add_argument('--run-url', default='')
    parser.add_argument('--title', default='', help='默认用 tag 作为标题')
    parser.add_argument('files', nargs='+', help='要上传的附件')
    args = parser.parse_args()

    token = os.environ.get('GITHUB_TOKEN', '')
    if not token:
        print('FAIL 缺少环境变量 GITHUB_TOKEN', file=sys.stderr)
        return 1

    notes = ''
    if args.notes_file:
        notes_path = pathlib.Path(args.notes_file)
        if not notes_path.exists():
            print(f'FAIL 找不到说明文件 {args.notes_file}', file=sys.stderr)
            return 1
        notes = notes_path.read_text(encoding='utf-8')

    release = call(f'{API}/repos/{args.repo}/releases/tags/{args.tag}', token, allow_404=True)
    if release is None:
        print(f'新建 Release {args.tag}')
        release = call(f'{API}/repos/{args.repo}/releases', token, method='POST', payload={
            'tag_name': args.tag,
            'name': args.title or args.tag,
            'generate_release_notes': True,
            'draft': False,
            'prerelease': False,
        })
        # 说明只在新建时前置一次，避免重跑时正文越叠越长
        call(f'{API}/repos/{args.repo}/releases/{release["id"]}', token, method='PATCH',
             payload={'body': build_body(notes, args.run_url, release.get('body') or '')})
    else:
        print(f'Reuse existing Release {args.tag}')

    release_id = release['id']
    upload_url = release.get('upload_url') or (
        f'{UPLOADS}/repos/{args.repo}/releases/{release_id}/assets{{?name,label}}')
    upload_base = upload_url.split('{', 1)[0]
    assets = call(f'{API}/repos/{args.repo}/releases/{release_id}/assets', token) or []
    existing = {a['name']: a for a in assets}

    for path_str in args.files:
        path = pathlib.Path(path_str)
        if not path.is_file():
            print(f'FAIL 附件不存在：{path_str}', file=sys.stderr)
            return 1
        if path.name in existing:
            print(f'替换已有附件 {path.name}')
            call(f'{API}/repos/{args.repo}/releases/assets/{existing[path.name]["id"]}',
                 token, method='DELETE')
        query = urllib.parse.urlencode({'name': path.name})
        asset = call(f'{upload_base}?{query}', token, method='POST',
                     payload=path.read_bytes(), content_type='application/octet-stream')
        print(f'上传 {path.name}（{path.stat().st_size / 1048576:.2f} MB）')
        print(f'  下载地址 {asset.get("browser_download_url", "(未知)")}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
