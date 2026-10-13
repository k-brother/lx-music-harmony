#!/usr/bin/env bash
# 发布一个版本：打 v* 标签并推送 → GitHub 上的「打包 HAP」自动出包并发布到 Release
# （本地不用出包，产物与 Release 都在云端生成）
#
# 用法（在工程根目录）：
#   ./scripts/release_tag.sh            # 用 AppScope/app.json5 的 versionName，拼成 v1.2.3
#   ./scripts/release_tag.sh v1.2.3     # 显式指定（必须与 versionName 一致，避免包内自报版本对不上）
#
# 会做的校验：工作区干净、标签不与 versionName 冲突、同名标签不存在。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

version="$(python3 - "${ROOT}/AppScope/app.json5" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding='utf-8').read()
match = re.search(r'"versionName"\s*:\s*"([^"]+)"', text)
if not match:
    print('')
else:
    print(match.group(1).strip())
PY
)"
if [ -z "${version}" ]; then
  echo "error: 读不到 AppScope/app.json5 里的 versionName" >&2
  exit 1
fi

tag="${1:-v${version}}"
if [ "${tag}" != "v${version}" ]; then
  echo "error: 标签 ${tag} 与 app.json5 里的 versionName ${version} 不一致。" >&2
  echo "       请先把 AppScope/app.json5 的 versionName / versionCode 改成 ${tag#v}，再重新发布。" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: 工作区有未提交改动，先提交再发布：" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "error: 本地已存在标签 ${tag}" >&2
  exit 1
fi

echo "当前分支：$(git rev-parse --abbrev-ref HEAD)  版本：${version}  标签：${tag}"
git tag -a "${tag}" -m "${tag}"

for remote in gitee github; do
  if git remote | grep -qx "${remote}"; then
    echo "== 推送标签到 ${remote} =="
    git push "${remote}" "${tag}"
  fi
done

echo
echo "已推送标签 ${tag}。GitHub 上会自动出包并创建 Release："
echo "  Actions : https://github.com/k-brother/lx-music-harmony/actions/workflows/build-hap.yml"
echo "  Releases: https://github.com/k-brother/lx-music-harmony/releases/tag/${tag}"
