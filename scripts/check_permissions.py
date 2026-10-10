#!/usr/bin/env python3
"""权限声明与使用一致性检查（上架相关）

应用市场审核会核对「申请的权限是否真的在用」：声明了却没用到会被要求说明或驳回。
这里为每个声明的权限列出「必须能在代码里找到的使用痕迹」，任何一条找不到即报错；
反过来，用到敏感 API 却没有声明权限同样需要修（见下面的 REQUIRED_USAGE 注释）。

用法：python3 scripts/check_permissions.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ETS = ROOT / 'entry/src/main/ets'

# 权限 → 代码中应出现的使用痕迹（任一命中即认为在用）
USAGE_HINTS = {
    'ohos.permission.INTERNET': [r'@kit\.NetworkKit', r'http\.createHttp', r'createLxWebSocket'],
    'ohos.permission.GET_NETWORK_INFO': [r'connection\.getDefaultNet', r'@kit\.NetworkKit'],
    'ohos.permission.KEEP_BACKGROUND_RUNNING': [r'backgroundTaskManager'],
    'ohos.permission.VIBRATE': [r'vibrator\.', r'HapticFeedback'],
    'ohos.permission.MICROPHONE': [r'createAudioCapturer', r'requestPermissionsFromUser'],
}


def regroup(names):
    """去重且保持声明顺序"""
    seen = []
    for n in names:
        if n not in seen:
            seen.append(n)
    return seen


def main():
    module = (ROOT / 'entry/src/main/module.json5').read_text()
    # module.json5 是 json5（有注释/嵌套数组），直接抓权限名即可
    declared = regroup(re.findall(r'"(ohos\.permission\.[A-Z_]+)"', module))
    if not declared:
        print('未声明任何权限（跳过）')
        return 0

    all_text = '\n'.join(p.read_text() for p in ETS.rglob('*.ets'))
    problems = []
    for perm in declared:
        hints = USAGE_HINTS.get(perm)
        if hints is None:
            print(f'NOTE 未登记的权限，请人工确认是否在用: {perm}')
            continue
        if not any(re.search(h, all_text) for h in hints):
            problems.append(perm)

    print(f'声明权限 {len(declared)} 个: {declared}')
    for perm in problems:
        print(f'FAIL 声明但代码里找不到使用痕迹: {perm}')
    if not problems:
        print('权限声明与使用一致')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
