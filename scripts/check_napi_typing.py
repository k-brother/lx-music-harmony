#!/usr/bin/env python3
"""原生模块（.so）默认导出的类型标注守卫。

DevEco 的 ArkTS 校验会报：

  Structural typing is not supported (arkts-no-structural-typing)

触发条件是「把 .so 默认导出的值赋给本地重复声明的接口」：

  interface InflateNapiModule { inflateBytes(...): ... }
  const inflateModule: InflateNapiModule = inflateNapiSo;   // 结构相同但不同名 -> 报红

ArkTS 不支持结构化类型：两个形状相同但声明不同的接口之间不能直接赋值。
正确做法是让 `native-modules.d.ts` 做唯一签名来源，直接调用模块方法：

  const result: ArrayBuffer | undefined = inflateNapiSo.inflateBytes(data);

本地声明接口 + `as` 转换是允许的（见 napi_quickjs.ets），但「带类型标注的直接赋值」
一定报红，这里把它钉死。

用法：python3 scripts/check_napi_typing.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'

SO_IMPORT = re.compile(r"^\s*import\s+([A-Za-z_]\w*)\s+from\s+'[^']*\.so'\s*;")
ANNOTATED_ASSIGN = re.compile(
    r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_]\w*)\s*:\s*([^=;]+?)\s*=\s*([A-Za-z_]\w*)\s*;")


def scan_file(path: pathlib.Path) -> list:
    lines = path.read_text().split('\n')
    so_names = set()
    for line in lines:
        match = SO_IMPORT.match(line)
        if match:
            so_names.add(match.group(1))
    if not so_names:
        return []
    problems = []
    for index, line in enumerate(lines, start=1):
        match = ANNOTATED_ASSIGN.match(line)
        if not match:
            continue
        target, declared, source = match.groups()
        if source in so_names:
            problems.append(
                f'{path.relative_to(ROOT.parent.parent)}:{index} 把 {source} 直接赋给接口 {declared.strip()}'
                f'（变量 {target}）；ArkTS 不支持结构化类型，会报 arkts-no-structural-typing。'
                f'请去掉本地重复声明的接口，直接调用模块方法')
    return problems


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob('*.ets')):
        problems.extend(scan_file(path))
    if problems:
        print('FAIL 原生模块类型标注（DevEco 会报红 arkts-no-structural-typing）:')
        print('\n'.join(problems))
        return 1
    print('原生模块（.so）类型标注正确（无结构化类型赋值）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
