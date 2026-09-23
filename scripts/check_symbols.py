"""系统符号渲染检查

`Image($r('sys.symbol.xxx'))` 在真机上不会渲染任何内容（系统符号是字体字形资源，
必须用 SymbolGlyph）。历史上一度全项目 47 个图标因此隐形，这里做静态防回归。

另外会把用到的符号名与 SDK 的符号名单比对：拼错名字时真机同样「什么都不显示」，
而编译器不会报错（例如把 text_bubble_left_2 写成 text_bubble_left）。
SDK 名单从 ets-loader/sysResource.js 读取；找不到 SDK 时只做上面的用法检查。

退出码：发现违规用法返回 1。
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
PATTERN = re.compile(r"Image\(\s*\$r\('sys\.symbol\.")
SYMBOL = re.compile(r"sys\.symbol\.([a-z0-9_]+)")

violations = []
used_symbols = set()
for path in sorted(root.rglob('*.ets')):
    text = path.read_text()
    for index, line in enumerate(text.split('\n'), start=1):
        if PATTERN.search(line):
            violations.append(f'{path.relative_to(root)}:{index}: {line.strip()}')
    for name in SYMBOL.findall(text):
        used_symbols.add(name)

for item in violations:
    print('FAIL', item)
print()
print('Image 加载系统符号的用法：', len(violations), '（应为 0，系统符号请用 SymbolGlyph）')


def sdk_symbol_names():
    """从 HarmonyOS SDK 的 ets-loader 资源表里取全部 sys.symbol 名字"""
    sdk_root = pathlib.Path.home() / 'Library/OpenHarmony/Sdk'
    if not sdk_root.exists():
        return None
    for js in sorted(sdk_root.glob('*/ets/build-tools/ets-loader/sysResource.js')):
        text = js.read_text(errors='ignore')
        names = set(re.findall(r'\n\s{8}([a-z0-9_]+): \d+,', text))
        if names:
            return names
    return None


sdk_names = sdk_symbol_names()
unknown = []
if sdk_names is None:
    print('未找到 SDK 符号名单，跳过符号名校验')
else:
    unknown = sorted(n for n in used_symbols if n not in sdk_names)
    print(f'用了 {len(used_symbols)} 个系统符号，SDK 名单里找不到的：{len(unknown)}')
    for n in unknown:
        print('FAIL 未在 SDK 符号名单中:', n)

sys.exit(1 if (violations or unknown) else 0)
