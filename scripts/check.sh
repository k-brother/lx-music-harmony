#!/usr/bin/env bash
# 一轮改动后的自检：未使用 import / 死代码 / i18n 对齐 / 功能对齐清单
# 任意目录下执行均可（脚本内部按自身位置定位工程根目录）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== 未使用的 import =="
python3 "${SCRIPT_DIR}/check_imports.py"

echo "== 未被引用的私有方法 =="
python3 "${SCRIPT_DIR}/check_dead.py"

echo "== i18n 词条对齐 =="
python3 "${SCRIPT_DIR}/check_i18n.py"

echo "== 系统符号渲染（SymbolGlyph）=="
python3 "${SCRIPT_DIR}/check_symbols.py"

echo "== 设置快照字段完整性 =="
python3 "${SCRIPT_DIR}/check_settings_copy.py"

echo "== 功能对齐清单 =="
python3 "${SCRIPT_DIR}/verify_features.py"

echo "全部检查通过"
