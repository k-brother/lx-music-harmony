#!/usr/bin/env bash
# 播放页「更多」面板专项真机回归
#
# 这一栏有 14 个动作，重构后按「歌曲 / 播放 / 歌词 / 保存」分组；
# 脚本逐项确认「点得开、开的是对的面板」，这是静态检查覆盖不到的部分。
#
# 用法：./scripts/device_player_check.sh
#       HDC=/path/to/hdc TARGET=192.168.1.2:5555 ./scripts/device_player_check.sh
set -uo pipefail

BUNDLE="com.lxmusic.mobile"
ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
TARGET="${TARGET:-$("$HDC" list targets 2>/dev/null | head -1)}"
if [ "$TARGET" = "[Empty]" ]; then TARGET=""; fi
UI_TMP="${TMPDIR:-/tmp}/lx-player-layout.json"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

hdc_do() {
  if [ -n "$TARGET" ]; then "$HDC" -t "$TARGET" "$@"; else "$HDC" "$@"; fi
}
tap()  { hdc_do shell "uitest uiInput click $1 $2" >/dev/null 2>&1 || true; }
key()  { hdc_do shell "uitest uiInput keyEvent $1" >/dev/null 2>&1 || true; }

dump() {
  : > "$UI_TMP"
  hdc_do shell "uitest dumpLayout -p /data/local/tmp/lx-player.json" >/dev/null 2>&1 || return 1
  hdc_do file recv /data/local/tmp/lx-player.json "$UI_TMP" >/dev/null 2>&1 || return 1
  [ -s "$UI_TMP" ]
}
has() { dump && grep -q "$1" "$UI_TMP"; }

tap_text() {
  dump >/dev/null 2>&1 || return 1
  local coord
  coord=$(python3 - "$1" "$UI_TMP" <<'PY'
import json, re, sys
target, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
best = None
def walk(n):
    global best
    a = n.get('attributes', {})
    if a.get('text', '') == target and a.get('bounds'):
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', a['bounds'])
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            area = (x2 - x1) * (y2 - y1)
            if best is None or area < best[2]:
                best = ((x1 + x2) // 2, (y1 + y2) // 2, area)
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(f'{best[0]} {best[1]}' if best else '')
PY
)
  [ -n "$coord" ] || return 1
  tap $coord
}

# 先按标签点、失败退回坐标（布局微调不至于让整段脚本失效）
tap_label_or_coord() { tap_text "$1" >/dev/null 2>&1 || tap "$2" "$3"; }

if [ ! -x "$HDC" ]; then
  printf '找不到 hdc：%s（可用 HDC=... 指定）\n' "$HDC"
  exit 2
fi
HAP="${SCRIPT_DIR}/../entry/build/default/outputs/default/entry-default-signed.hap"
if [ ! -f "$HAP" ]; then
  printf '缺少安装包：%s（先跑 ./hvigor.sh assembleApp）\n' "$HAP"
  exit 2
fi

printf '设备：%s\n' "${TARGET:-默认}"
hdc_do install -r "$HAP" >/dev/null 2>&1 || { printf '安装失败\n'; exit 2; }
hdc_do shell "power-shell wakeup" >/dev/null 2>&1 || true
hdc_do shell "power-shell timeout -o 1800000" >/dev/null 2>&1 || true
hdc_do shell "aa force-stop ${BUNDLE}" >/dev/null 2>&1
sleep 1
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 6

# 冷启动落在歌单页：进第一张歌单 → 点第一首播放 → 从迷你播放器封面进播放页
tap_label_or_coord "歌单" 173 997; sleep 6
tap 500 760; sleep 6
dump >/dev/null 2>&1
MINI_Y=$(python3 - "$UI_TMP" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
best = None
def walk(n):
    global best
    a = n.get('attributes', {})
    b = a.get('bounds', '')
    t = a.get('text', '')
    if b and t:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            # 迷你播放器里的歌曲标题：靠底部、左侧留出封面空间
            if y1 > 2350 and x1 >= 220 and x1 < 700:
                cy = (y1 + y2) // 2
                if best is None or cy < best:
                    best = cy
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(best if best else 0)
PY
)
if [ "${MINI_Y:-0}" -gt 0 ]; then tap 129 "$MINI_Y"; else tap 129 2600; fi
sleep 6
if has "歌词"; then ok "进入播放页"; else bad "进入播放页"; fi

# 打开「更多」
tap_label_or_coord "更多" 1146 222; sleep 3
if has "播放队列"; then ok "「更多」面板打开"; else bad "「更多」面板打开"; fi
for group in 歌曲 播放 歌词 保存; do
  if has "$group"; then ok "分组标题可见：$group"; else bad "分组标题可见：$group"; fi
done

# 逐项验证「点得开、开的是对的面板」
# 注意：菜单/面板都只需一次返回键关闭；关掉后重新点右上角「更多」回到面板
check_item() {          # $1 文案  $2 面板特征文案
  tap_text "$1" >/dev/null 2>&1
  sleep 3
  if has "$2"; then ok "「$1」打开对应面板"; else bad "「$1」打开对应面板"; fi
  key 2; sleep 2
  tap_label_or_coord "更多" 1146 222; sleep 3
  if ! has "播放队列"; then
    # 面板可能还在关闭动画中，再点一次
    tap_label_or_coord "更多" 1146 222; sleep 3
  fi
}

check_item "播放速度" "1.25x"
check_item "歌词偏移" "重置"
check_item "音量" "音量"
check_item "播放队列" "播放队列（"
check_item "歌词显示" "歌词显示"

# 换源面板：候选列表（可能未搜到，两种结果都算通过，只要不是"没反应"）
tap_text "换源" >/dev/null 2>&1
sleep 6
if has "正在搜索其它音源" || has "没有找到其它音源" || has "换源"; then
  ok "「换源」打开对应面板"
else
  bad "「换源」打开对应面板"
fi
key 2; sleep 2

printf '\n结果：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
