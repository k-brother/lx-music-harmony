#!/usr/bin/env python3
"""服务初始化调用检查

「服务写好了 initialize()，但全项目没人调用」这种情况很隐蔽：
编译能过、代码看着完整，现象却是「重启后自动同步 / 自动备份不跑，
设置页还把开关显示成关闭」——只有真机重启才发现。

本轮就是这样查出 SyncService.initialize() 与 BackupService.initialize() 两个都没人调。

判定：service/ 与 core/ 下导出的单例，如果定义了 initialize()/init()，
就必须在定义文件之外出现 `<单例>.<方法>(` 的调用。

用法：python3 scripts/check_service_init.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
METHODS = ('initialize', 'init')
# 例外的初始化入口：由同文件内的包装函数代调（initSettings → settingsService.init）
ALLOW_SAME_FILE = {
    'settingsService': '由 initSettings() 包装调用（同文件）',
}


def main() -> int:
    findings = []
    def code_only(text: str) -> str:
        """去掉整行注释，避免「注释掉的调用」被当成调用方（实测会骗过检查）"""
        kept = []
        for line in text.split('\n'):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*') or stripped.startswith('/*'):
                continue
            kept.append(line)
        return '\n'.join(kept)

    for p in sorted(ROOT.rglob('*.ets')):
        rel = str(p.relative_to(ROOT))
        if not (rel.startswith('service/') or rel.startswith('core/')):
            continue
        text = p.read_text()
        singles = re.findall(r'export const (\w+) = ', text) + re.findall(r'export default (\w+)', text)
        if not singles:
            continue
        found: list = []
        for method in METHODS:
            if re.search(r'^\s{2}(?:async\s+)?' + method + r'\s*\(', text, re.M):
                found.append(method)
        if not found:
            continue
        for single in singles:
            if single == single.lower() and single.islower():
                continue
            for method in found:
                same_file_ok = (single in ALLOW_SAME_FILE
                                and re.search(re.escape(single) + r'\.' + method + r'\(', text) is not None)
                if same_file_ok:
                    continue
                callers = []
                for other in ROOT.rglob('*.ets'):
                    if other == p:
                        continue
                    if re.search(re.escape(single) + r'\.' + method + r'\(', code_only(other.read_text())):
                        callers.append(str(other.relative_to(ROOT)))
                if not callers:
                    findings.append(f'{rel}: {single}.{method}() 没有任何调用方（服务等于没初始化）')
    print('\n'.join(findings) if findings else 'all service initializers are wired')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
