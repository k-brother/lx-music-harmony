"""死代码检查

1. 私有方法与模块级函数：文件内除声明外没有出现即视为未引用；
2. 类成员（方法/构建器）：名字在全项目只出现一次即视为无人调用 ——
   这类成员之前溜过检查（例如 PlayerService.getPlayModeLabel 写死中文、
   又没有任何调用方）。ArkUI 的生命周期与渲染回调由框架调用，显式豁免。

退出码：发现问题返回 1。
"""
import re
import pathlib
import sys

# 允许从任意目录执行：以脚本位置定位工程根目录
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
report = []

# ArkUI 由框架调用的回调，不在源码里出现
FRAMEWORK_MEMBERS = {
    'aboutToAppear', 'aboutToDisappear', 'aboutToReuse', 'aboutToRecycle',
    'onPageShow', 'onPageHide', 'onBackPress', 'onBackPressed', 'onReady',
    'build', 'onWindowStageCreate', 'onWindowStageDestroy',
    'onForeground', 'onBackground', 'onCreate', 'onDestroy',
    'onConfigurationUpdate', 'onMemoryLevel', 'onDraw', 'onChange',
    # IDataSource：由 LazyForEach 内部调用（LazyDataSource 的四个必备成员）
    'totalCount', 'getData', 'registerDataChangeListener', 'unregisterDataChangeListener',
}

files = sorted(root.rglob('*.ets'))
texts = {}
for p in files:
    texts[p] = p.read_text()
all_text = '\n'.join(texts.values())

for p in files:
    text = texts[p]
    lines = text.split('\n')
    # private methods & module-level functions
    for i, line in enumerate(lines):
        m = re.search(r'^\s*(?:private\s+|export\s+)?(?:async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\(', line)
        if not m:
            continue
        name = m.group(1)
        if name in ('if','for','while','switch','catch','return','function','constructor','get','set','describe'):
            continue
        if '=>' in line and 'function' not in line:
            continue
        if not (line.strip().startswith('private ') or line.strip().startswith('function ') or line.strip().startswith('export function')):
            continue
        occurrences = 0
        for j, other in enumerate(lines):
            if j == i:
                continue
            if re.search(r'\b' + re.escape(name) + r'\b', other):
                occurrences += 1
        if occurrences == 0:
            report.append(f'{p}:{i+1} unreferenced: {line.strip()[:90]}')

    # 类成员方法（含 public / @Builder / @Styles）
    for i, line in enumerate(lines):
        m = re.match(
            r'^  (?:@\w+\s+)?(?:private\s+|public\s+|protected\s+|static\s+|async\s+)*'
            r'([A-Za-z_$][A-Za-z0-9_$]*)\s*\(', line)
        if not m:
            continue
        name = m.group(1)
        if name in ('if', 'for', 'while', 'switch', 'catch', 'return', 'function',
                    'constructor', 'get', 'set') or name in FRAMEWORK_MEMBERS:
            continue
        # 成员访问形态 xxx.name
        member_uses = len(re.findall(r'\.' + re.escape(name) + r'\b', all_text))
        all_uses = len(re.findall(r'\b' + re.escape(name) + r'\b', all_text))
        if member_uses == 0 and all_uses - 1 <= 0:
            report.append(f'{p}:{i+1} unreferenced member: {line.strip()[:90]}')

    # 只写不读的 @State（声明后在本文件内没有任何其它引用）
    for i, line in enumerate(lines):
        m = re.match(r'\s*@State\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*[:=]', line)
        if not m:
            continue
        name = m.group(1)
        others = 0
        for j, other in enumerate(lines):
            if j != i and re.search(r'\b' + re.escape(name) + r'\b', other):
                others += 1
        if others == 0:
            report.append(f'{p}:{i+1} unused @State: {line.strip()[:90]}')

print('\n'.join(report) if report else 'no unreferenced private/function declarations')
print('total', len(report))
sys.exit(1 if report else 0)
