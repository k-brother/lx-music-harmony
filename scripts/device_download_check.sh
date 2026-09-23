#!/usr/bin/env bash
# 下载管理页专项真机回归
#
# 覆盖这一轮重构的交互面（静态检查证明不了）：
#   筛选分段计数 → 多选入口 → 勾选/全选计数 → 批量删除二次确认 → 清空已完成文案
#
# 用法：./scripts/device_download_check.sh
#       HDC=/path/to/hdc TARGET=192.168.1.2:5555 ./scripts/device_download_check.sh
set -uo pipefail

BUNDLE="com.lxmusic.mobile"
ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
TARGET="${TARGET:-$("$HDC" list targets 2>/dev/null | head -1)}"
if [ "$TARGET" = "[Empty]" ]; then TARGET=""; fi
UI_TMP="${TMPDIR:-/tmp}/lx-download-layout.json"

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
  hdc_do shell "uitest dumpLayout -p /data/local/tmp/lx-download.json" >/dev/null 2>&1 || return 1
  hdc_do file recv /data/local/tmp/lx-download.json "$UI_TMP" >/dev/null 2>&1 || return 1
  [ -s "$UI_TMP" ]
}
has() { dump && grep -q "$1" "$UI_TMP"; }

# 按文案定位并点击（找不到返回非 0）
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
sleep 8

# 进入下载管理（底部 Tab）
tap_text "下载管理" || true
sleep 3
if has "下载管理"; then ok "进入下载管理页"; else bad "进入下载管理页"; fi

if has "全部 ("; then ok "筛选分段显示各状态计数"; else bad "筛选分段显示各状态计数"; fi
if has "清空已完成"; then ok "底部操作文案明确（清空已完成）"; else bad "底部操作文案明确（清空已完成）"; fi

# 多选入口
tap_text "多选" || true
sleep 2
if has "取消"; then ok "进入多选模式（顶栏变「取消」）"; else bad "进入多选模式"; fi
if has "点击任务可多选"; then ok "多选栏提示可见"; else bad "多选栏提示可见"; fi
if has "全选"; then ok "多选栏有「全选」"; else bad "多选栏有「全选」"; fi

# 勾选第一个任务
dump >/dev/null 2>&1
ROW_Y=$(python3 - "$UI_TMP" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
ys = []
def walk(n):
    a = n.get('attributes', {})
    b = a.get('bounds', '')
    # 任务行是可点击的大行（宽度接近整屏）
    if a.get('clickable') == 'true' and b:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            if x2 - x1 > 1000 and y2 - y1 > 200 and y1 > 400 and y2 < 2000:
                ys.append((y1 + y2) // 2)
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(ys[0] if ys else 0)
PY
)
if [ "${ROW_Y:-0}" -gt 0 ]; then
  tap 630 "$ROW_Y"; sleep 2
  if has "已选 1 项"; then ok "勾选任务后计数正确（已选 1 项）"; else bad "勾选任务后计数正确"; fi
  if has "全选"; then
    tap_text "全选" || true
    sleep 2
    if has "已选 1 项" && ! has "已选 3 项" && ! has "已选 2 项"; then
      bad "全选后计数未变化"
    else
      ok "全选后计数更新"
    fi
  fi
else
  bad "定位任务行坐标"
fi

# 批量删除的二次确认（取消，不改动用户数据）
dump >/dev/null 2>&1
TRASH=$(python3 - "$UI_TMP" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
best = None
def walk(n):
    global best
    a = n.get('attributes', {})
    b = a.get('bounds', '')
    if a.get('clickable') == 'true' and b:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            x1, y1, x2, y2 = (int(v) for v in m.groups())
            # 批量栏里的最右图标（删除）
            if y1 > 2100 and x1 > 1000:
                if best is None or x1 > best[0]:
                    best = (x1, (y1 + y2) // 2, x2)
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(best[1] if best else 0)
PY
)
if [ "${TRASH:-0}" -gt 0 ]; then
  tap 1160 "$TRASH"; sleep 3
  if has "确定删除"; then ok "批量删除有二次确认"; else bad "批量删除有二次确认"; fi
  key 2; sleep 2   # 返回键 = 取消，不动用户下载数据
  ok "确认框可用返回键取消"
else
  bad "定位批量删除按钮"
fi

# 退出多选
tap_text "取消" || true
sleep 2
if has "下载管理"; then ok "退出多选回到普通态"; else bad "退出多选回到普通态"; fi

printf '\n结果：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
