"""设置项字段完整性检查。

背景：settingsService.get() 返回的是 copyOf() 手工逐字段拷贝的快照，
新增设置项时如果漏了 copyOf 这一处，编译能过、设置也能落盘，
但运行时读到的永远是默认值（真机上就表现为「设置明明改了却不生效」）。
这里把 AppSettings 的字段与 copyOf 的赋值做一次比对，漏一个就失败。
"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
types_text = (root / 'service/settings/SettingsTypes.ets').read_text()
service_text = (root / 'service/SettingsService.ets').read_text()

# AppSettings 接口体
start = types_text.index('export interface AppSettings {')
body = types_text[start:]
body = body[:body.index('\n}')]
fields = re.findall(r'^\s{2}([A-Za-z_][A-Za-z0-9_]*)\s*\??:', body, re.M)

# copyOf 里被赋值的字段
copy_start = service_text.index('private copyOf(')
copy_body = service_text[copy_start:]
copy_body = copy_body[:copy_body.index('\n  }')]
assigned = re.findall(r'copy\.([A-Za-z_][A-Za-z0-9_]*)\s*=', copy_body)
copied = set(assigned)
dups = sorted({f for f in assigned if assigned.count(f) > 1})

missing = [f for f in fields if f not in copied]
extra = sorted(copied - set(fields))

failed = False
if missing:
    print('FAIL copyOf 漏掉的设置字段:', ', '.join(missing))
    failed = True
if extra:
    print('FAIL copyOf 里的未知字段:', ', '.join(extra))
    failed = True
if dups:
    print('FAIL copyOf 重复赋值:', ', '.join(dups))
    failed = True

if failed:
    sys.exit(1)

print(f'PASS 设置快照字段完整（{len(fields)} 个字段全部拷贝）')
