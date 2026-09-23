#!/usr/bin/env bash
# 播放队列手势专项真机回归
#
# 覆盖「只有真机才能发现」的那类问题（此前只有静态断言）：
#   1. 拖拽手柄必须真的能排序（系统拖放 onDragStart/onDrop 在真机上不生效）；
#   2. 拖拽不能误触发整行点击（曾经拖完会莫名切歌）；
#   3. 拖拽结束后「正在播放的那首」不能被换掉；
#   4. 长按移除、列表滚动不能被拖拽改动弄坏。
#
# 用法：./scripts/device_queue_check.sh
set -uo pipefail

BUNDLE="com.lxmusic.mobile"
ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
TARGET="${TARGET:-$("$HDC" list targets 2>/dev/null | head -1)}"
if [ "$TARGET" = "[Empty]" ]; then TARGET=""; fi
UI_TMP="${TMPDIR:-/tmp}/lx-queue-layout.json"

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
  hdc_do shell "uitest dumpLayout -p /data/local/tmp/lx-queue.json" >/dev/null 2>&1 || return 1
  hdc_do file recv /data/local/tmp/lx-queue.json "$UI_TMP" >/dev/null 2>&1 || return 1
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

# 打印队列面板里前 N 行的标题（只取行内主标题：字号 15、位于行高范围内）
queue_titles() {
  dump >/dev/null 2>&1 || return 1
  python3 - "$UI_TMP" "$1" <<'PY'
import json, re, sys
path, limit = sys.argv[1], int(sys.argv[2])
d = json.load(open(path))
rows = []
def walk(n):
    a = n.get('attributes', {})
    t, b = a.get('text', ''), a.get('bounds', '')
    if t and b:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            # 队列行：标题/歌手从 x≈162 开始；y>420 跳开顶部「封面/歌词」分段标题
            if x1 >= 150 and x2 > 900 and y1 > 420:
                rows.append((y1, t))
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
rows.sort()
titles = [t for _, t in rows]
# 每行有标题+歌手两段，隔一个取一个（歌手行同样从 x≈162 开始）
print('|'.join(titles[:limit * 2]))
PY
}

if [ ! -x "$HDC" ]; then
  printf '找不到 hdc：%s\n' "$HDC"
  exit 2
fi
HAP="${SCRIPT_DIR}/../entry/build/default/outputs/default/entry-default-signed.hap"
[ -f "$HAP" ] || { printf '缺少安装包：%s\n' "$HAP"; exit 2; }

printf '设备：%s\n' "${TARGET:-默认}"
hdc_do install -r "$HAP" >/dev/null 2>&1 || { printf '安装失败\n'; exit 2; }
hdc_do shell "power-shell wakeup" >/dev/null 2>&1 || true
hdc_do shell "power-shell timeout -o 1800000" >/dev/null 2>&1 || true
hdc_do shell "aa force-stop ${BUNDLE}" >/dev/null 2>&1
sleep 1
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 6

# 造队列：进第一张歌单 → 播放全部 → 迷你播放器 → 播放页 → 更多 → 播放队列
tap_text "歌单" >/dev/null 2>&1; sleep 3
tap 173 997; sleep 6
tap_text "播放全部" >/dev/null 2>&1; sleep 6
dump >/dev/null 2>&1
MINI_Y=$(python3 - "$UI_TMP" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
best = None
def walk(n):
    global best
    a = n.get('attributes', {})
    t, b = a.get('text', ''), a.get('bounds', '')
    if t and b:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            if y1 > 2350 and 220 < x1 < 700:
                cy = (y1 + y2) // 2
                if best is None or cy < best:
                    best = cy
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(best if best else 2600)
PY
)
tap 129 "$MINI_Y"; sleep 5
tap 1155 232; sleep 3
tap_text "播放队列" >/dev/null 2>&1; sleep 3
if has "播放队列（"; then ok "打开播放队列"; else bad "打开播放队列"; fi

BEFORE=$(queue_titles 2)
printf '  队列前两行：%s\n' "$BEFORE"

# 拖拽手柄把第 1 行下移一行：手柄 x≈1160，行高 64vp；注入 240px ≈ 71vp（约 1.1 行）
hdc_do shell "hilog -r" >/dev/null 2>&1
hdc_do shell "uitest uiInput swipe 1160 400 1160 640 900" >/dev/null 2>&1
sleep 2
if hdc_do shell "hilog -x" 2>/dev/null | grep -q "QueueSheet: drag end: 0 -> 1"; then
  ok "拖拽手势被识别（0 -> 1）"
else
  bad "拖拽手势被识别"
fi

AFTER=$(queue_titles 2)
printf '  拖拽后前两行：%s\n' "$AFTER"
if [ "$AFTER" != "$BEFORE" ]; then ok "队列顺序发生变化"; else bad "队列顺序发生变化"; fi

# 正在播放的那首不能被换掉
if hdc_do shell "hilog -x" 2>/dev/null | grep -q "PlayerService: updateAvMetadata"; then
  bad "拖拽不应触发切歌"
else
  ok "拖拽没有误触发切歌"
fi

# 长按整行仍然出「从队列移除」（第 1 行中心 y≈376）
hdc_do shell "uitest uiInput longClick 500 400" >/dev/null 2>&1
sleep 3
if has "从队列移除"; then ok "长按仍可移除"; else bad "长按仍可移除"; fi
key 2; sleep 2

printf '\n结果：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
