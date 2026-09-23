#!/usr/bin/env python3
"""原生模块（.so）统一加载守卫。三处分工，谁都不能越界：

  core/napi/NativeModules.ets     唯一 `import *.so` 的地方（加载/缓存/兜底/日志）
  core/napi/NativeModuleTypes.ets 唯一声明句柄接口的地方
  native-modules.d.ts             只声明「有这几个原生库」，不重复声明形状

规则一：只有 NativeModules.ets 允许 `import ... from 'lib*.so'`。其它模块要用原生
        能力，一律 `getInflateModule()` / `getQuickJSModule()` /
        `getQuickJSLoaderModule()` 取句柄 —— 用了哪些原生库、怎么加载，看一个文件就够。

规则二：句柄接口只允许在 NativeModuleTypes.ets 声明一份。DevEco 的 ArkTS 校验对
        「形状相同但声明不同」的接口互相赋值会直接报红：

          Structural typing is not supported (arkts-no-structural-typing)

        典型踩法（真踩过）：本地再写一遍接口，然后把 .so 默认导出赋给它：

          interface InflateNapiModule { inflateBytes(...): ... }
          const inflateModule: InflateNapiModule = inflateNapiSo;   // 报红

        句柄类型也不能用类型位置的 typeof 推导（arkts-no-type-query）。

用法：python3 scripts/check_native_modules.py
"""
import pathlib
import re
import sys

ETS_ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
REGISTRY_REL = 'core/napi/NativeModules.ets'
REGISTRY = ETS_ROOT / REGISTRY_REL
TYPES_REL = 'core/napi/NativeModuleTypes.ets'
TYPES_FILE = ETS_ROOT / TYPES_REL

SO_IMPORT = re.compile(r"^\s*import\s+([A-Za-z_]\w*)\s+from\s+'(lib[\w]*\.so)'\s*;")
ANNOTATED_ASSIGN = re.compile(
    r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_]\w*)\s*:\s*([^=;]+?)\s*=\s*([A-Za-z_]\w*)\s*;")
LOCAL_INTERFACE = re.compile(r"^\s*(?:export\s+)?(?:interface|class)\s+([A-Za-z_]\w*)")
GETTER = re.compile(r"^export function get[A-Za-z0-9_]*Module\(", re.M)
HANDLE_INTERFACE = re.compile(r"^\s*(?:export\s+)?interface\s+([A-Za-z_]\w*NativeModule)\b")


def scan_file(path: pathlib.Path, is_registry: bool) -> list:
    lines = path.read_text().split('\n')
    rel = path.relative_to(ETS_ROOT)
    problems = []
    so_names = set()
    for line in lines:
        match = SO_IMPORT.match(line)
        if match:
            so_names.add(match.group(1))
            if not is_registry:
                problems.append(
                    f'{rel} 直接 import 了原生库 {match.group(2)}；'
                    f'原生库只能在 {REGISTRY_REL} 加载，这里请改用 getXxxModule()')
    if is_registry:
        getters = len(GETTER.findall(path.read_text()))
        if getters < len(so_names):
            problems.append(
                f'{rel} 导入了 {len(so_names)} 个原生库，却只有 {getters} 个 getXxxModule() 出口；'
                f'每个原生库都要有对应的取句柄函数')
    elif 'NativeModuleTypes.ets' not in path.name:
        for index, line in enumerate(lines, start=1):
            match = HANDLE_INTERFACE.match(line)
            if match:
                problems.append(
                    f'{rel}:{index} 重复声明了原生库句柄接口 {match.group(1)}；'
                    f'句柄接口只能在 {TYPES_REL} 声明一份（否则 arkts-no-structural-typing 报红）')
    local_types = set()
    for line in lines:
        match = LOCAL_INTERFACE.match(line)
        if match:
            local_types.add(match.group(1))
    for index, line in enumerate(lines, start=1):
        match = ANNOTATED_ASSIGN.match(line)
        if not match:
            continue
        target, declared, source = match.groups()
        declared = declared.strip()
        if source in so_names and declared in local_types:
            problems.append(
                f'{rel}:{index} 把 {source} 赋给本地声明的 {declared}（变量 {target}）会报 '
                f'arkts-no-structural-typing；句柄接口请从 {TYPES_REL} 引用，用 `as` 收敛')
    return problems


def main() -> int:
    if not REGISTRY.exists():
        print(f'FAIL 原生模块统一加载入口缺失：{REGISTRY_REL}')
        return 1
    if not TYPES_FILE.exists():
        print(f'FAIL 原生模块句柄类型声明缺失：{TYPES_REL}')
        return 1
    problems = []
    for path in sorted(ETS_ROOT.rglob('*.ets')):
        problems.extend(scan_file(path, path == REGISTRY))
    if problems:
        print('FAIL 原生模块（.so）加载方式不统一:')
        print('\n'.join(problems))
        return 1
    print('原生模块（.so）统一加载：入口唯一、类型无重复声明')
    return 0


if __name__ == '__main__':
    sys.exit(main())
