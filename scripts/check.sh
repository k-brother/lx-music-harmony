#!/usr/bin/env bash
# 一轮改动后的自检：未使用 import / 死代码 / i18n 对齐 / 功能对齐清单
# 任意目录下执行均可（脚本内部按自身位置定位工程根目录）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== 未使用的 import =="
python3 "${SCRIPT_DIR}/check_imports.py"

echo "== 导入风格（@kit 能力集入口）=="
python3 "${SCRIPT_DIR}/check_kit_imports.py"

echo "== 未被引用的私有方法 =="
python3 "${SCRIPT_DIR}/check_dead.py"

echo "== 零引用的导出（有实现没入口）=="
python3 "${SCRIPT_DIR}/check_unused_exports.py"

echo "== 入口可达性（死模块）=="
python3 "${SCRIPT_DIR}/check_reachable.py"

echo "== 路由一致性 =="
python3 "${SCRIPT_DIR}/check_routes.py"

echo "== AppStorage 绑定闭环 =="
python3 "${SCRIPT_DIR}/check_storage_bindings.py"

echo "== 权限声明与使用一致性 =="
python3 "${SCRIPT_DIR}/check_permissions.py"

echo "== 无障碍（纯图标按钮需可朗读）=="
python3 "${SCRIPT_DIR}/check_accessibility.py"

echo "== 迷你播放条覆盖 =="
python3 "${SCRIPT_DIR}/check_mini_player.py"

echo "== 2in1 键盘操作 =="
python3 "${SCRIPT_DIR}/check_keyboard.py"

echo "== 播放队列落盘出口 =="
python3 "${SCRIPT_DIR}/check_queue_persist.py"

echo "== 记住滚动位置覆盖 =="
python3 "${SCRIPT_DIR}/check_scroll_memory.py"

echo "== 列表行文案出口 =="
python3 "${SCRIPT_DIR}/check_row_texts.py"

echo "== 真机脚本断言一致性 =="
python3 "${SCRIPT_DIR}/check_device_assertions.py"

echo "== 错误文案多语言 =="
python3 "${SCRIPT_DIR}/check_error_i18n.py"

echo "== 服务初始化调用 =="
python3 "${SCRIPT_DIR}/check_service_init.py"

echo "== 在线页失败态 =="
python3 "${SCRIPT_DIR}/check_error_states.py"

echo "== 一多（响应式）覆盖 =="
python3 "${SCRIPT_DIR}/check_responsive.py"

echo "== i18n 词条对齐 =="
python3 "${SCRIPT_DIR}/check_i18n.py"

echo "== 词条占位符 =="
python3 "${SCRIPT_DIR}/check_i18n_placeholders.py"

echo "== @Builder 状态参数 =="
python3 "${SCRIPT_DIR}/check_builder_state_args.py"

echo "== 组件定时器清理 =="
python3 "${SCRIPT_DIR}/check_timer_cleanup.py"

echo "== 组件订阅清理 =="
python3 "${SCRIPT_DIR}/check_subscription_cleanup.py"

echo "== 设计 token 收口 =="
python3 "${SCRIPT_DIR}/check_design_tokens.py"

echo "== 通用属性链噪音 =="
python3 "${SCRIPT_DIR}/check_style_noise.py"

echo "== 资源引用 =="
python3 "${SCRIPT_DIR}/check_resources.py"

echo "== 系统符号渲染（SymbolGlyph）=="
python3 "${SCRIPT_DIR}/check_symbols.py"

echo "== 设置快照字段完整性 =="
python3 "${SCRIPT_DIR}/check_settings_copy.py"

echo "== 恢复默认设置覆盖完整性 =="
python3 "${SCRIPT_DIR}/check_settings_reset.py"

echo "== 设置项入口/消费者 =="
python3 "${SCRIPT_DIR}/check_settings_ui.py"

echo "== 功能对齐清单 =="
python3 "${SCRIPT_DIR}/verify_features.py"

echo "全部检查通过"
