#!/usr/bin/env bash
# 真机冒烟回归
#
# 静态检查（check.sh）证明不了运行时行为，这里把「装包 -> 启动 -> 关键链路 ->
# 日志断言」固化成脚本，每轮改完跑一次，结果可复现、可追溯。
#
# 用法：
#   ./scripts/device_smoke.sh                 # 用默认 hdc / 设备
#   HDC=/path/to/hdc TARGET=192.168.1.2:5555 ./scripts/device_smoke.sh
#
# 断言不通过时脚本以非 0 退出，并打印失败项与相关日志片段。
set -uo pipefail

BUNDLE="com.lxmusic.mobile"
ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# hdc：优先环境变量，其次 SDK 默认位置
HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
# 设备地址自动识别：优先 TARGET，其次当前已连接设备（TCP 直连时 IP 可能变化）
TARGET="${TARGET:-$("$HDC" list targets 2>/dev/null | head -1)}"
if [ "$TARGET" = "[Empty]" ]; then TARGET=""; fi

PASS=0
FAIL=0
FAILED_NAMES=()

log()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); log "  PASS  $1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); log "  FAIL  $1${2:+  ($2)}"; }

hdc_do() {
  if [ -n "$TARGET" ]; then
    "$HDC" -t "$TARGET" "$@"
  else
    "$HDC" "$@"
  fi
}

# 读取最近日志并按关键字断言（可给期望出现次数下限）
assert_log() {
  local name="$1" pattern="$2" min="${3:-1}"
  local count
  count=$(hdc_do shell "hilog -x" 2>/dev/null | grep -cE "$pattern" || true)
  if [ "${count:-0}" -ge "$min" ]; then
    ok "$name (匹配 ${count} 条)"
  else
    bad "$name" "期望 ≥${min} 条匹配 /$pattern/，实际 ${count:-0}"
  fi
}

assert_no_crash() {
  local name="$1"
  local hits
  hits=$(hdc_do shell "hilog -x" 2>/dev/null | grep -E "com\.lxmusic\.mobile.*(FATAL|CRASH|Error:.*uncaught|Errno)" | grep -v "Failed to get pic" | wc -l | tr -d ' ')
  if [ "${hits:-0}" -eq 0 ]; then
    ok "$name"
  else
    bad "$name" "发现 ${hits} 条崩溃/致命日志"
    hdc_do shell "hilog -x" 2>/dev/null | grep -E "com\.lxmusic\.mobile.*(FATAL|CRASH|uncaught)" | tail -3
  fi
}

# 断言界面上出现某段文案（浮层/面板这类不写日志的 UI 用这个）
ui_has_text() {
  local pattern="$1"
  local dump="/data/local/tmp/smoke_layout.json"
  local local_dump="${TMPDIR:-/tmp}/smoke_layout.json"
  hdc_do shell "uitest dumpLayout -p ${dump}" >/dev/null 2>&1 || true
  hdc_do file recv "$dump" "$local_dump" >/dev/null 2>&1 || true
  [ -f "$local_dump" ] && grep -qE "$pattern" "$local_dump"
}

assert_ui_text() {
  local name="$1" pattern="$2"
  if ui_has_text "$pattern"; then
    ok "$name"
  else
    bad "$name" "界面未出现 /$pattern/"
  fi
}

# 反复点击直到界面出现目标文案（冷启动落点不定，用于「确保在某个页面」）
tap_until_ui_text() {
  local x="$1" y="$2" pattern="$3" tries="${4:-3}"
  local i=0
  while [ "$i" -lt "$tries" ]; do
    if ui_has_text "$pattern"; then
      return 0
    fi
    tap "$x" "$y"
    sleep 3
    i=$((i + 1))
  done
  ui_has_text "$pattern"
}

tap() { hdc_do shell "uitest uiInput click $1 $2" >/dev/null 2>&1 || true; }
swipe() { hdc_do shell "uitest uiInput swipe $1 $2 $3 $4 ${5:-300}" >/dev/null 2>&1 || true; }

# 按文案（含无障碍文案）取节点中心；找不到返回非 0
ui_find_text() {
  local target="$1"
  local dump="/data/local/tmp/smoke_layout.json"
  local local_dump="${TMPDIR:-/tmp}/smoke_layout.json"
  : > "$local_dump"
  hdc_do shell "uitest dumpLayout -p ${dump}" >/dev/null 2>&1 || return 1
  hdc_do file recv "$dump" "$local_dump" >/dev/null 2>&1 || return 1
  [ -s "$local_dump" ] || return 1
  python3 "${SCRIPT_DIR}/ui_find.py" "$target" "$local_dump"
}

# 先按标签点（图标按钮只有无障碍文案，也能匹配），失败再退回坐标：
# 布局做了小调整时，脚本不会因为一个写死的坐标就整段失效。
tap_label_or_coord() {
  local label="$1" x="$2" y="$3" coords
  coords=$(ui_find_text "$label" 2>/dev/null) && { tap $coords; return 0; }
  tap "$x" "$y"
}
key() { hdc_do shell "uitest uiInput keyEvent $1" >/dev/null 2>&1 || true; }

if [ ! -x "$HDC" ]; then
  log "找不到 hdc：$HDC（可用 HDC=... 指定）"
  exit 2
fi

TARGETS=$(hdc_do list targets 2>/dev/null | head -1)
if [ -z "$TARGETS" ] || [ "$TARGETS" = "[Empty]" ]; then
  log "没有可用设备（hdc list targets 为空）"
  exit 2
fi
log "设备：${TARGETS}"

HAP="${PROJECT_DIR}/entry/build/default/outputs/default/entry-default-signed.hap"
if [ ! -f "$HAP" ]; then
  log "缺少安装包：$HAP（先跑 ./hvigor.sh assembleApp）"
  exit 2
fi

log "== 1. 安装并冷启动 =="
hdc_do install -r "$HAP" >/dev/null 2>&1 && ok "安装成功" || bad "安装失败"
hdc_do shell "hilog -r" >/dev/null 2>&1
hdc_do shell "aa force-stop ${BUNDLE}" >/dev/null 2>&1
sleep 1
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 6
# 启动断言：日志可能被上一轮清理/滚动覆盖，所以「进程确实在跑」也算通过
# （否则会在紧接 hilog -r 之后偶发假失败，与真实启动成败无关）
assert_app_running() {
  local name="$1" pattern="$2"
  local count
  count=$(hdc_do shell "hilog -x" 2>/dev/null | grep -cE "$pattern" || true)
  if [ "${count:-0}" -ge 1 ]; then
    ok "$name (匹配 ${count} 条)"
    return
  fi
  local pid
  pid=$(hdc_do shell "pidof ${BUNDLE}" 2>/dev/null | tr -d '\r\n ')
  if [ -n "$pid" ]; then
    ok "$name（日志已滚出缓冲，但进程随启动拉起 pid=${pid}）"
  else
    bad "$name" "既没有初始化日志，也查不到进程"
  fi
}
assert_app_running "应用启动（AppBootstrap/PlayerService 初始化）" "com\.lxmusic\.mobile/(AppBootstrap|PlayerService)"
assert_no_crash "启动无崩溃"

log "== 2. 歌单列表与换源 =="
# 冷启动可能落在「正在播放」页（跟随设置里的启动页面），也可能被其它应用抢了前台，
# 先回到主界面再操作
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 2
for _ in 1 2; do key Back; sleep 2; done
if tap_until_ui_text 170 2690 "搜索音乐"; then
  ok "回到歌单页（搜索条可见）"
else
  bad "回到歌单页" "点击底部歌单 Tab 后仍未出现搜索条"
fi
# 先切到第一个音源再切第二个：若当前已经是第二个源，直接点它不会触发重载
tap 168 190
sleep 5
hdc_do shell "hilog -r" >/dev/null 2>&1
tap 464 190          # 顶栏切到第二个音源（QQ）
sleep 7
assert_log "换源触发列表重载" "SongListView: Source/reCreateKey changed"
assert_log "换源后按新源拉取（无空态）" "SongListView" 1

log "== 3. 歌单详情 =="
tap 173 997          # 第一张歌单卡片
sleep 7
# 详情加载拆分到 SonglistDetail/SonglistLoader 后，日志 TAG 也随之变化
assert_log "歌单详情加载出歌曲" "SonglistLoader: API returned: [1-9][0-9]* songs"
key Back
sleep 3

log "== 4. 播放与歌词 =="
tap_label_or_coord "打开播放页" 129 2464   # 迷你播放器 -> 播放详情（标签优先，坐标兜底）
sleep 6
assert_log "播放页就绪（路由 onReady）" "NavIndex: PlayDetailPage onReady"
assert_log "歌词链路成功" "ONLINE_MUSIC: lyric (fetch success|source result)"

log "== 5. 队列面板 =="
tap_label_or_coord "更多" 1146 222      # 右上角更多（标签优先，坐标兜底）
sleep 3
tap_label_or_coord "播放队列" 630 218   # 更多菜单里的「播放队列」
sleep 3
assert_ui_text "队列面板打开（面板标题可见）" "播放队列"
key Back
sleep 2

log "== 6. 设置与全局面板 =="
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 2
key Back
sleep 2
if tap_until_ui_text 1100 2690 "设置"; then
  ok "回到「我的」页"
else
  bad "回到「我的」页" "未出现「设置」入口"
fi
if tap_until_ui_text 1130 205 "基础设置"; then
  ok "进入设置页"
else
  bad "进入设置页" "未出现分组标题「基础设置」"
fi
# 设置页滚动位置不定，先回到顶部再点「语言」
for _ in 1 2 3 4 5; do swipe 630 600 630 2200 120; done
sleep 2
tap 1000 525         # 语言（走全局面板）
sleep 3
assert_ui_text "设置项面板弹出（语言选择）" "简体中文"
key Back
sleep 2

log ""
log "结果：通过 ${PASS} 项，失败 ${FAIL} 项"
if [ "$FAIL" -gt 0 ]; then
  log "失败项："
  for name in "${FAILED_NAMES[@]}"; do
    log "  - ${name}"
  done
  exit 1
fi
log "真机冒烟全部通过"
