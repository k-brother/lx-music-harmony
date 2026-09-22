import re, pathlib, collections

# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
loc = (root / 'service/LocalizationService.ets').read_text()
zh_part = loc[loc.index('function buildZhCN'):loc.index('function buildEnUS')]
en_part = loc[loc.index('function buildEnUS'):loc.index('const zhCNMap')]

def keys(text):
    ks = re.findall(r"m\.set\('([^']+)'", text)
    dup = [k for k, c in collections.Counter(ks).items() if c > 1]
    return ks, dup

zh, zh_dup = keys(zh_part)
en, en_dup = keys(en_part)
zhset, enset = set(zh), set(en)
print('zh keys', len(zhset), 'en keys', len(enset))
print('zh duplicates:', zh_dup)
print('en duplicates:', en_dup)
print('missing in en:', sorted(zhset - enset))
print('missing in zh:', sorted(enset - zhset))

used = collections.Counter()
for p in root.rglob('*.ets'):
    if p.name == 'LocalizationService.ets':
        continue
    text = p.read_text()
    for k in re.findall(r"\bt\('([^']+)'\)", text):
        used[k] += 1
    for k in re.findall(r"\btf\('([^']+)'", text):
        used[k] += 1
    for k in re.findall(r"t\(([A-Za-z_][A-Za-z0-9_]*)\)", text):
        pass

print('used distinct keys', len(used))
# 动态拼接的键（t(`source_${type}_${id}`)）在静态扫描里看不到，这里显式放行
DYNAMIC_PREFIXES = ('source_alias_', 'source_real_')
unused = sorted(k for k in (zhset - set(used)) if not k.startswith(DYNAMIC_PREFIXES))
print('defined but unused count', len(unused))
print(unused)
missing = sorted(set(used) - zhset)
print('used but undefined', len(missing))
print(missing)
