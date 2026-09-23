#!/usr/bin/env python3
"""组件订阅清理检查

组件里订阅了播放器/事件总线/设置变化等回调，却忘记在 aboutToDisappear 取消，
页面销毁后回调仍会触发（本项目真机上出现过「页面已退出还在 setState」的隐患）。

判定：文件里出现了订阅类调用，但整个文件没有任何取消订阅的痕迹
（unsub / off / removeXxxListener / detach / clear）即报告。

用法：python3 scripts/check_subscription_cleanup.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

# 订阅类调用（新增订阅 API 时在这里补一行）
SUBSCRIPTIONS = [
    r'playerService\.on[A-Z]\w*\(',
    r'sleepTimerService\.onStateChange\(',
    r'syncService\.addStatusListener\(',
    r'stateEvent\.on\(',
    r'appEvent\.on\(',
    r'\bon\(EventTypes\.',
    r'watchSettings\(',
    r'onThemeChange\(',
    r'onListChange\(',
    r'backgroundRunningManager\.on[A-Z]\w*\(',
]

# 取消痕迹（大小写都算：listUnsubscribe / settingsUnsub / unsubscribeXxx 都在用）
CLEANUP = re.compile(r'unsub|\.off\(|remove\w*Listener|\.detach\(\)|clearTimeout|clearInterval', re.I)


def main():
    problems = []
    for p in sorted(ROOT.rglob('*.ets')):
        text = p.read_text()
        if '@Component' not in text and 'struct ' not in text:
            continue
        found = []
        for pattern in SUBSCRIPTIONS:
            hits = re.findall(pattern, text)
            if hits:
                found.append(f'{pattern} x{len(hits)}')
        if not found:
            continue
        if not CLEANUP.search(text):
            problems.append(f'{p.relative_to(ROOT)}: 订阅 {found}，但没有任何取消订阅痕迹')

    print('\n'.join(problems) if problems else 'no dangling subscriptions')
    print('total', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
