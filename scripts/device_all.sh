#!/usr/bin/env bash
# 一次性跑完全部真机脚本（里程碑用，别每轮都跑）
#
# 为什么单独有这么一个脚本：五个专项脚本各自会装包 + 冷启动，
# 逐个跑要十几分钟。这里按顺序跑一遍并把结果汇总成一行，方便「一天/一个里程碑只跑一次」。
# 日常改动用 `./hvigor.sh assembleApp && ./scripts/check.sh`（几秒）就够了。
#
# 用法：./scripts/device_all.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HDC="${HDC:-$HOME/Library/OpenHarmony/Sdk/26.0.0/toolchains/hdc}"

SUITES=(
  "device_smoke.sh:主链路冒烟"
  "device_player_check.sh:播放页"
  "device_queue_check.sh:队列手势"
  "device_download_check.sh:下载页"
  "device_settings_check.sh:设置页"
)

PASSED=()
FAILED=()
START=$(date +%s)

for entry in "${SUITES[@]}"; do
  script="${entry%%:*}"
  label="${entry##*:}"
  printf '\n===== %s（%s）=====\n' "$label" "$script"
  if bash "${SCRIPT_DIR}/${script}"; then
    PASSED+=("$label")
  else
    FAILED+=("$label")
  fi
done

ELAPSED=$(( $(date +%s) - START ))
printf '\n===== 汇总（耗时 %ds）=====\n' "$ELAPSED"
printf '通过：%s\n' "${PASSED[*]:-无}"
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '失败：%s\n' "${FAILED[*]}"
  exit 1
fi
printf '全部真机脚本通过\n'
