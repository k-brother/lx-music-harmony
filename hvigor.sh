#!/usr/bin/env bash
# 使用 DevEco Studio 自带的 Node 与 hvigor，避免与本机 Node 版本不一致。
# 用法（在 harmony 目录）: ./hvigor.sh assembleApp
# 支持 macOS 和 Windows (Git Bash / MSYS2 / Cygwin)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 检测 MSYS/CYGWIN 环境并转换 Windows 路径
is_msys() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# 将 Windows 路径转换为 MSYS 路径
to_msys_path() {
  local path="$1"
  if is_msys && [[ "$path" =~ ^[A-Za-z]: ]]; then
    # C:\xxx → /c/xxx
    echo "$path" | sed -e 's/^\([A-Za-z]\):/\/\L\1/' -e 's/\\/\//g'
  else
    echo "$path"
  fi
}

# 尝试在指定路径查找可执行文件
find_executable() {
  local path="$1"
  if [[ -x "$path" ]]; then
    echo "$path"
    return 0
  fi
  # Windows 下可能没有 .exe 后缀
  if is_msys && [[ -x "${path}.exe" ]]; then
    echo "${path}.exe"
    return 0
  fi
  return 1
}

# 查找 DevEco Studio 安装目录
find_deveco_studio() {
  local candidate=""
  if is_msys; then
    # Windows 典型安装路径
    for dir in \
      "/c/Program Files/Huawei/DevEco Studio" \
      "/c/Program Files (x86)/Huawei/DevEco Studio" \
      "$HOME/AppData/Local/Programs/Huawei/DevEco Studio"; do
      if [[ -d "$dir" ]]; then
        candidate="$dir"
        break
      fi
    done
  else
    # macOS
    if [[ -d "/Applications/DevEco-Studio.app" ]]; then
      candidate="/Applications/DevEco-Studio.app"
    fi
  fi
  echo "$candidate"
}

# ========== 主逻辑 ==========
DEVECO_STUDIO=""
NODE=""
HVIGORW=""

if [[ -n "${DEVECO_NODE:-}" && -n "${DEVECO_HVIGORW:-}" ]]; then
  # 环境变量显式指定，优先使用
  NODE="$DEVECO_NODE"
  HVIGORW="$DEVECO_HVIGORW"
elif is_msys; then
  # Windows: 自动探测
  DEVECO_STUDIO="$(find_deveco_studio)"
  if [[ -z "$DEVECO_STUDIO" ]]; then
    echo "error: DevEco Studio not found. Set DEVECO_NODE and DEVECO_HVIGORW env vars." >&2
    exit 1
  fi

  # 查找 node
  local node_paths=(
    "$DEVECO_STUDIO/tools/node/bin/node"
    "$DEVECO_STUDIO/tools/node/bin/node.exe"
    "$DEVECO_STUDIO/plugins/unicorn/toolchains/node/bin/node"
    "$DEVECO_STUDIO/plugins/unicorn/toolchains/node/bin/node.exe"
  )
  for p in "${node_paths[@]}"; do
    local converted
    converted="$(to_msys_path "$p")"
    if NODE="$(find_executable "$converted")"; then
      break
    fi
  done
  if [[ -z "$NODE" ]]; then
    echo "error: Node not found in DevEco Studio at $DEVECO_STUDIO" >&2
    exit 1
  fi

  # 查找 hvigorw.js
  local hvigor_paths=(
    "$DEVECO_STUDIO/tools/hvigor/bin/hvigorw.js"
    "$DEVECO_STUDIO/tools/hvigor/hvigorw.js"
  )
  for p in "${hvigor_paths[@]}"; do
    local converted
    converted="$(to_msys_path "$p")"
    if [[ -f "$converted" ]]; then
      HVIGORW="$converted"
      break
    fi
  done
  if [[ -z "$HVIGORW" ]]; then
    echo "error: hvigorw.js not found in DevEco Studio at $DEVECO_STUDIO" >&2
    exit 1
  fi
else
  # macOS: 使用默认值
  DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
  export DEVECO_SDK_HOME

  NODE="${DEVECO_NODE:-/Applications/DevEco-Studio.app/Contents/tools/node/bin/node}"
  HVIGORW="${DEVECO_HVIGORW:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js}"

  if [[ ! -x "$NODE" ]] && [[ ! -x "${NODE}.exe" ]]; then
    echo "error: Node not found at $NODE (set DEVECO_NODE)" >&2
    exit 1
  fi
  if [[ ! -f "$HVIGORW" ]]; then
    echo "error: hvigorw.js not found at $HVIGORW (set DEVECO_HVIGORW)" >&2
    exit 1
  fi
fi

exec "$NODE" "$HVIGORW" "$@"
