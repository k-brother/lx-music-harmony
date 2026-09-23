import re, pathlib, collections
import sys

# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
# 词条表已按语言拆到 service/localization/{ZhCN,EnUS}.ets，这里直接读两张表
zh_part = (root / 'service/localization/ZhCN.ets').read_text()
en_part = (root / 'service/localization/EnUS.ets').read_text()

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

# 中英必须一一对应，且不留「定义了没人用」「用了却没定义」的词条：
# 前者是死文案，后者会让界面直接显示原始 key（曾经真的漏过，如
# sync_msg_connect_fail 与 sync_msg_connect_failed 拼写不一致）。
problems = []
if zh_dup or en_dup:
    problems.append(f'重复词条 zh={zh_dup} en={en_dup}')
if zhset - enset or enset - zhset:
    problems.append(f'中英不一致 缺 en={sorted(zhset - enset)} 缺 zh={sorted(enset - zhset)}')
if unused:
    problems.append(f'定义但未使用 {len(unused)} 条: {unused}')
if missing:
    problems.append(f'使用但未定义 {len(missing)} 条: {missing}')
if problems:
    print('FAIL ' + '; '.join(problems))
    sys.exit(1)
print('i18n 检查通过')
