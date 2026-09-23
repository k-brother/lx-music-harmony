#!/usr/bin/env bash
# 设置页专项真机回归
#
# 覆盖两类「静态检查抓不到」的问题：
# 1. 设置项选完，右侧「当前值」必须立刻刷新（ForEach key 回归）；
# 2. 「下载文件名」必须真的落库（copyOf 漏字段时，UI 正常但值永远读默认）。
#
# 用法：./scripts/device_settings_check.sh
#       HDC=/path/to/hdc TARGET=192.168.1.2:5555 ./scripts/device_settings_check.sh
set -uo pipefail

BUNDLE="com.lxmusic.mobile"
ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"
TARGET="${TARGET:-$("$HDC" list targets 2>/dev/null | head -1)}"
if [ "$TARGET" = "[Empty]" ]; then TARGET=""; fi
UI_TMP="${TMPDIR:-/tmp}/lx-settings-layout.json"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

hdc_do() {
  if [ -n "$TARGET" ]; then "$HDC" -t "$TARGET" "$@"; else "$HDC" "$@"; fi
}
tap()   { hdc_do shell "uitest uiInput click $1 $2" >/dev/null 2>&1 || true; }
swipe() { hdc_do shell "uitest uiInput swipe $1 $2 $3 $4 ${5:-200}" >/dev/null 2>&1 || true; }
key()   { hdc_do shell "uitest uiInput keyEvent $1" >/dev/null 2>&1 || true; }

dump() {
  : > "$UI_TMP"
  hdc_do shell "uitest dumpLayout -p /data/local/tmp/lx-settings.json" >/dev/null 2>&1 || return 1
  hdc_do file recv /data/local/tmp/lx-settings.json "$UI_TMP" >/dev/null 2>&1 || return 1
  [ -s "$UI_TMP" ]
}
has() { dump && grep -q "$1" "$UI_TMP"; }

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
hdc_do shell "power-shell timeout -o 1800000" >/dev/null 2>&1 || true
hdc_do shell "aa force-stop ${BUNDLE}" >/dev/null 2>&1
sleep 1
hdc_do shell "aa start -a ${ABILITY} -b ${BUNDLE}" >/dev/null 2>&1
sleep 6

# 进「我的 → 设置」
key 2; sleep 2
key 2; sleep 2
tap 1102 2693; sleep 3
tap 1130 205; sleep 3
if has "基础设置"; then ok "进入设置页"; else bad "进入设置页"; fi

# 滚到「下载设置」分组
found=0
for _ in $(seq 1 8); do
  swipe 630 2400 630 900 300
  sleep 1
  if has "下载文件名"; then found=1; break; fi
done
if [ "$found" = "1" ]; then ok "找到「下载文件名」设置项"; else bad "找到「下载文件名」设置项"; fi

# 取该行当前值（默认「歌名 - 歌手」）
if has "歌名 - 歌手"; then ok "默认值为「歌名 - 歌手」"; else bad "默认值为「歌名 - 歌手」"; fi

# 选「歌手 - 歌名」：行内文案必须立刻刷新（不重启）
dump >/dev/null 2>&1
ROW_Y=$(python3 - "$UI_TMP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hit = []
def walk(n):
    a = n.get('attributes', {})
    if a.get('text', '') == '下载文件名':
        b = a.get('bounds', '')
        if b:
            ys = b.split('][')[0].split(',')[1]
            hit.append(int(ys))
    for c in n.get('children', []) or []:
        walk(c)
walk(d)
print(hit[0] + 40 if hit else 0)
PY
)
if [ "${ROW_Y:-0}" -gt 0 ]; then
  tap 600 "$ROW_Y"; sleep 3
  tap 592 1486   # 面板第二项：歌手 - 歌名
  sleep 3
  if has "歌手 - 歌名"; then ok "选择后面板关闭且行内文案立刻刷新"; else bad "选择后行内文案立刻刷新"; fi
  # 再切回默认值，验证反向也生效并恢复设备状态
  tap 600 "$ROW_Y"; sleep 3
  tap 592 1336   # 面板第一项：歌名 - 歌手
  sleep 3
  if has "歌名 - 歌手"; then ok "切回默认值同样即时刷新"; else bad "切回默认值即时刷新"; fi
else
  bad "定位「下载文件名」行坐标"
fi

# 落库校验：copyOf 漏字段时这里会暴露（UI 正常但值读不到）
STORED=$(hdc_do shell "cat /data/app/el2/100/base/com.lxmusic.mobile/haps/entry/preferences/lx_music_preferences" 2>/dev/null \
  | tr '<' '\n' | grep 'setting.download.fileName' | sed 's/.*>//')
if [ "$STORED" = "name-singer" ]; then
  ok "设置已落库并恢复默认（setting.download.fileName=name-singer）"
else
  bad "设置落库值异常：${STORED:-空}"
fi

printf '\n结果：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
