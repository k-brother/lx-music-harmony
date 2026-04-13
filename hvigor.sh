#!/usr/bin/env bash
# 使用 DevEco Studio 自带的 Node 与 hvigor，避免与本机 Node 版本不一致。
# 用法（在 harmony 目录）: ./hvigor.sh assembleHap -p product=default
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

: "${DEVECO_SDK_HOME:=/Applications/DevEco-Studio.app/Contents/sdk}"
export DEVECO_SDK_HOME

NODE="${DEVECO_NODE:-/Applications/DevEco-Studio.app/Contents/tools/node/bin/node}"
HVIGORW="${DEVECO_HVIGORW:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js}"
# 与 DevEco「外部模型」一致：DevEco-Studio.app/Contents/tools/node/bin/node …/hvigorw.js

if [[ ! -x "$NODE" ]]; then
  echo "error: Node not found at $NODE (set DEVECO_NODE)" >&2
  exit 1
fi
if [[ ! -f "$HVIGORW" ]]; then
  echo "error: hvigorw.js not found at $HVIGORW (set DEVECO_HVIGORW)" >&2
  exit 1
fi

exec "$NODE" "$HVIGORW" "$@"
