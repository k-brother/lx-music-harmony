#!/usr/bin/env python3
"""导入风格收敛：统一用 @kit.* 能力集入口。

HarmonyOS NEXT 的推荐写法是 `import { x } from '@kit.XxxKit'`，
`@ohos.*` 单模块路径虽然还能编译，但一个工程里两套写法并存时，
升级/迁移时很容易漏改一半（本轮就把 108 个文件的 136 处导入统一过来了）。
这里把"已有 kit 等价入口的模块"钉住，避免又写回旧路径。

用法：python3 scripts/check_kit_imports.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
# 报错时打印相对工程根的路径（harmony/entry/src/main/ets/...）
PROJECT_ROOT = ROOT.parents[3]

# @ohos.* 模块 -> 应该使用的 kit 入口
KIT_EQUIVALENTS = {
    '@ohos.hilog': '@kit.PerformanceAnalysisKit',
    '@ohos.file.fs': '@kit.CoreFileKit',
    '@ohos.file.picker': '@kit.CoreFileKit',
    '@ohos.data.preferences': '@kit.ArkData',
    '@ohos.window': '@kit.ArkUI',
    '@ohos.arkui.UIContext': '@kit.ArkUI',
    '@ohos.util': '@kit.ArkTS',
    '@ohos.security.cryptoFramework': '@kit.CryptoArchitectureKit',
    '@ohos.pasteboard': '@kit.BasicServicesKit',
    '@ohos.i18n': '@kit.LocalizationKit',
    '@ohos.app.ability.UIAbility': '@kit.AbilityKit',
    '@ohos.app.ability.Configuration': '@kit.AbilityKit',
}

IMPORT_RE = re.compile(r"from\s+'(@ohos\.[A-Za-z0-9_.]+)'")


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob('*.ets')):
        for lineno, line in enumerate(path.read_text().split('\n'), start=1):
            if not line.startswith('import '):
                continue
            match = IMPORT_RE.search(line)
            if not match:
                continue
            module = match.group(1)
            kit = KIT_EQUIVALENTS.get(module)
            if kit:
                problems.append(f'{path.relative_to(PROJECT_ROOT)}:{lineno} 用 {kit} 代替 {module}')
    if problems:
        print('FAIL 存在可用 kit 入口的旧式导入:')
        print('\n'.join(problems))
        return 1
    print('导入风格统一（已迁移模块全部走 @kit.*）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
