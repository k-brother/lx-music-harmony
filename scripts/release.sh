#!/usr/bin/env bash
# 出包（上架用）：用 build-profile.json5 里的 release 产品与 LXMusic 签名配置
# 打一个已签名的 HAP，并把产物路径打出来。
#
# 用法（在 harmony 目录）：./scripts/release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

echo "== 出包前自检 =="
"${SCRIPT_DIR}/check.sh"

echo "== Release 构建（product=release / signingConfig=LXMusic）=="
./hvigor.sh assembleHap --mode module \
  -p module=entry@default \
  -p product=release \
  -p buildMode=release

OUT="${ROOT}/entry/build/release/outputs/default"
echo "== 产物 =="
ls -la "${OUT}"/*.hap
