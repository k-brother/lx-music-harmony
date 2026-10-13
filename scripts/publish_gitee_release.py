#!/usr/bin/env python3
"""把打好的 HAP 同步到 Gitee 的「发行版」（附件可下载）。

为什么需要单独这一步：GitHub Releases 里的安装包在中国大陆下载经常很慢，
而 Gitee 是主要面向国内用户的，两侧都挂一份体验最好。Gitee 侧不承担构建
（它的托管构建同样没有 DevEco/鸿蒙 SDK），只做"镜像发行版 + 附件"。

认证：Gitee 私人令牌（Gitee → 设置 → 安全设置 → 私人令牌，勾 projects 即可）。
仓库里不放令牌，运行机上放到一个文件里，路径由仓库变量 `GITEE_TOKEN_FILE` 指定。

行为：按 tag 找发行版 → 没有就用同一个 tag 新建（正文 = 说明文件内容）→
上传附件（同名附件先删再传，重跑安全；删不掉就跳过并提示，不中断发布）。

用法：
  python3 scripts/publish_gitee_release.py \
      --repo tkbrother/lxmusic --tag v1.0.0 \
      --token-file ~/dev-material/gitee-token \
      --notes-file .github/RELEASE_NOTES.md \
      dist/*.hap
"""
import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

API = 'https://gitee.com/api/v5'
USER_AGENT = 'lx-music-harmony-release'


class GiteeError(RuntimeError):
    pass


def call(url: str, method: str = 'GET', params=None, payload=None,
         content_type: str = 'application/json', allow_404: bool = False,
         timeout: int = 120):
    if params:
        url = f'{url}?{urllib.parse.urlencode(params)}'
    data = None
    headers = {'User-Agent': USER_AGENT}
    if payload is not None:
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode('utf-8')
        headers['Content-Type'] = content_type
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf-8', 'replace')
        if error.code == 404 and allow_404:
            return None
        raise GiteeError(f'{method} {url} -> HTTP {error.code}\n{detail}') from None
    except urllib.error.URLError as error:
        raise GiteeError(f'{method} {url} -> 网络错误 {error.reason}') from None


def encode_multipart(fields: dict, files: dict):
    """标准库拼 multipart/form-data（Gitee 附件上传必须用这个）。"""
    boundary = f'----lxmusic{uuid.uuid4().hex}'
    body = bytearray()
    for name, value in fields.items():
        body += (f'--{boundary}\r\n'
                 f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                 f'{value}\r\n').encode('utf-8')
    for name, (filename, content) in files.items():
        body += (f'--{boundary}\r\n'
                 f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                 f'Content-Type: application/octet-stream\r\n\r\n').encode('utf-8')
        body += content + b'\r\n'
    body += f'--{boundary}--\r\n'.encode('utf-8')
    return bytes(body), f'multipart/form-data; boundary={boundary}'


def find_release(repo: str, tag: str, token: str):
    releases = call(f'{API}/repos/{repo}/releases',
                    params={'access_token': token, 'per_page': 100}) or []
    for release in releases:
        if release.get('tag_name') == tag:
            return release
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', required=True, help='owner/name（Gitee 上的）')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--token-file', required=True)
    parser.add_argument('--notes-file', default='')
    parser.add_argument('--target', default='', help='新建发行版时关联的分支（默认仓库默认分支）')
    parser.add_argument('--dry-run', action='store_true', help='只打印要做什么，不调接口')
    parser.add_argument('files', nargs='+')
    args = parser.parse_args()

    token_path = pathlib.Path(args.token_file).expanduser()
    if not token_path.is_file():
        print(f'FAIL 找不到令牌文件 {token_path}', file=sys.stderr)
        return 1
    token = token_path.read_text(encoding='utf-8').strip()
    if not token:
        print(f'FAIL 令牌文件是空的：{token_path}', file=sys.stderr)
        return 1

    notes = ''
    if args.notes_file:
        notes_path = pathlib.Path(args.notes_file)
        if not notes_path.is_file():
            print(f'FAIL 找不到说明文件 {args.notes_file}', file=sys.stderr)
            return 1
        notes = notes_path.read_text(encoding='utf-8')

    missing = [f for f in args.files if not pathlib.Path(f).is_file()]
    if missing:
        print(f'FAIL 附件不存在：{", ".join(missing)}', file=sys.stderr)
        return 1

    if args.dry_run:
        print(f'[dry-run] repo={args.repo} tag={args.tag} 附件={args.files}')
        return 0

    try:
        release = find_release(args.repo, args.tag, token)
        if release is None:
            print(f'Gitee 上新建发行版 {args.tag}')
            payload = {'access_token': token, 'tag_name': args.tag, 'name': args.tag,
                       'body': notes.strip()}
            if args.target:
                payload['target_commitish'] = args.target
            release = call(f'{API}/repos/{args.repo}/releases', method='POST', payload=payload)
        else:
            print(f'复用已有发行版 {args.tag}（id={release.get("id")}）')

        release_id = release.get('id')
        if not release_id:
            raise GiteeError(f'创建发行版失败，返回：{release}')

        assets = {a.get('name'): a for a in (release.get('assets') or [])}
        for path_str in args.files:
            path = pathlib.Path(path_str)
            if path.name in assets:
                asset_id = assets[path.name].get('id')
                print(f'删除同名旧附件 {path.name}（id={asset_id}）')
                try:
                    call(f'{API}/repos/{args.repo}/releases/{release_id}/attach_files/{asset_id}',
                         method='DELETE', params={'access_token': token})
                except GiteeError as error:
                    print(f'  删不掉（{error}），继续上传，可能变成两个同名附件', file=sys.stderr)
            body, content_type = encode_multipart(
                {'access_token': token}, {'file': (path.name, path.read_bytes())})
            asset = call(f'{API}/repos/{args.repo}/releases/{release_id}/attach_files',
                         method='POST', payload=body, content_type=content_type)
            print(f'上传 {path.name}（{path.stat().st_size / 1048576:.2f} MB）')
            print(f'  下载地址 {asset.get("browser_download_url") or asset}')
        print(f'Gitee 发行版：https://gitee.com/{args.repo}/releases/tag/{args.tag}')
        return 0
    except GiteeError as error:
        print(f'FAIL {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
