#!/usr/bin/env bash
# 真机 UI 操作小工具（人工排查 / 临时脚本用）
#
# 目的：避免「dump 读到上一次的旧文件」和「坐标写死在脚本里」这两类坑。
# 用法（source 进来）：
#   source scripts/ui.sh
#   ui_tap_text 评论            # 按文案找节点并点它的中心
#   ui_wait_for 评论 3          # 等界面出现某文案
#   ui_logs_from_now            # 清空日志缓冲，只看之后的日志
#   ui_log_has "PlayerService"  # 断言日志里出现某关键字
#
# 注意：请在 harmony/ 目录下 `source scripts/ui.sh`（脚本目录按当前目录推断，
# 因为 zsh 的 -l 模式下 BASH_SOURCE 为空）。

UI_HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
# 设备地址自动识别：优先 TARGET，其次已连接设备，最后用 CONNECT 重连
UI_TARGET="${TARGET:-$("$UI_HDC" list targets 2>/dev/null | head -1)}"
if [ "$UI_TARGET" = "[Empty]" ]; then UI_TARGET=""; fi
UI_TMP="${TMPDIR:-/tmp}/lx-ui-layout.json"
# 设备走 TCP 连接时偶尔会掉线，这里记住地址以便自动重连。
# 地址是本机环境相关的东西，不写死在仓库里：用 CONNECT=ip:port 传入，例如
#   CONNECT=192.168.1.2:5555 source scripts/ui.sh
UI_CONNECT="${CONNECT:-}"

ui_hdc() {
  if [ -n "$UI_TARGET" ]; then "$UI_HDC" -t "$UI_TARGET" "$@"; else "$UI_HDC" "$@"; fi
}

# 确保设备在线（掉线就用 CONNECT 重连一次）
ui_ensure_device() {
  local targets
  targets=$("$UI_HDC" list targets 2>/dev/null | head -1)
  if [ -n "$targets" ] && [ "$targets" != "[Empty]" ]; then
    return 0
  fi
  if [ -z "$UI_CONNECT" ]; then
    echo "设备未连接；如走 TCP 调试请用 CONNECT=ip:port 重新 source 本脚本" >&2
    return 1
  fi
  "$UI_HDC" tconn "$UI_CONNECT" >/dev/null 2>&1 || true
  sleep 2
  targets=$("$UI_HDC" list targets 2>/dev/null | head -1)
  [ -n "$targets" ] && [ "$targets" != "[Empty]" ]
}

# 拉取一份最新的界面树（先删本地文件，避免 recv 失败时读到旧内容）
ui_dump() {
  ui_ensure_device || return 1
  # 先清空本地文件：recv 失败时不会读到上一次的旧界面树
  : > "$UI_TMP"
  ui_hdc shell "uitest dumpLayout -p /data/local/tmp/lx-ui.json" >/dev/null 2>&1 || return 1
  ui_hdc file recv /data/local/tmp/lx-ui.json "$UI_TMP" >/dev/null 2>&1 || return 1
  [ -s "$UI_TMP" ]
}

ui_has() {
  ui_dump || return 1
  grep -q "$1" "$UI_TMP"
}

# 按文案找节点中心坐标（输出 "x y"）
ui_find() {
  ui_dump || return 1
  python3 "${UI_DIR}/ui_find.py" "$1" "$UI_TMP"
}

ui_tap() { ui_hdc shell "uitest uiInput click $1 $2" >/dev/null 2>&1; }

# 先按标签点（无障碍文案也匹配），找不到再退回坐标：
# 这样布局做了小调整时，脚本不会因为一个写死的坐标就整段失效。
ui_tap_label_or_coord() {
  local label="$1" x="$2" y="$3"
  if ui_tap_text "$label" >/dev/null 2>&1; then
    return 0
  fi
  ui_tap "$x" "$y"
}

# 按文案点击（找不到返回非 0）
ui_tap_text() {
  local coords
  coords=$(ui_find "$1") || return 1
  ui_tap $coords
}

# 等界面出现某文案
ui_wait_for() {
  local text="$1" tries="${2:-3}" pause="${3:-3}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if ui_has "$text"; then return 0; fi
    sleep "$pause"
    i=$((i + 1))
  done
  ui_has "$text"
}

ui_logs_from_now() { ui_hdc shell "hilog -r" >/dev/null 2>&1; }
ui_log_has() { ui_hdc shell "hilog -x" 2>/dev/null | grep -qE "$1"; }
ui_log_tail() { ui_hdc shell "hilog -x" 2>/dev/null | grep -E "$1" | tail -"${2:-8}"; }

# 脚本目录：优先 harmony/scripts，其次当前目录
if [ -f "$(pwd)/scripts/ui_find.py" ]; then
  UI_DIR="$(pwd)/scripts"
else
  UI_DIR="$(pwd)"
fi
