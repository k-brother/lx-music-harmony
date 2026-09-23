#!/usr/bin/env python3
"""真机脚本断言与代码的一致性检查

真机批量回归（device_*.sh）用「日志 TAG + 关键片段」和「UI 文案」做断言。
代码重构后日志 TAG 可能改名（本轮就发现：歌单详情的加载日志从 `SonglistDetail`
搬到 `SonglistLoader` 之后，脚本里的断言已经对不上了），而这类不一致只有真机跑起来
才会暴露——那正是我们最不想浪费的环节。

判定（保守，只查最不会误报的两件事）：
1. `assert_log` 期望的 TAG（`Name:` 前缀）必须在代码里出现；
2. `assert_ui_text` 期望的文案必须能在中英词条表或代码里找到。

用法：python3 scripts/check_device_assertions.py
"""
import pathlib
import re
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = PROJECT / 'scripts'
ETS = PROJECT / 'entry/src/main/ets'
ASSERT_LOG = re.compile(r'assert_log\s+"([^"]+)"\s+"([^"]+)"')
ASSERT_UI = re.compile(r'assert_ui_text\s+"([^"]+)"\s+"([^"]+)"')
# 共享日志器：页面名是参数，日志由统一组件打（如导航目的地的 onReady 日志），
# 这类断言的关键词不会出现在「页面名同名的那份文件」里，需要显式映射到日志实现处。
SHARED_LOG_TAGS = {
    'NavIndex': 'components/ui/AppDestination.ets',
}


def code_files() -> list:
    """(相对路径, 原文, 归一化空白后的文本)"""
    out = []
    for p in ETS.rglob('*.ets'):
        text = p.read_text()
        out.append((str(p.relative_to(ETS)), text, ' '.join(text.split())))
    return out


def message_fragment(pattern: str) -> str:
    """取断言里的关键词：用于定位「打这条日志」的那段代码

    日志模板里有 %{public}s 这类占位，直接整段比对永远匹配不上；
    这里只取长度 ≥4 的英文单词，按「全部出现」判定归属文件。
    """
    tail = pattern.split(':', 1)[1] if ':' in pattern else pattern
    piece = tail.split('|')[0]
    words = re.findall(r'[A-Za-z_]{4,}', piece)
    return ' '.join(words)


def main() -> int:
    files = code_files()
    code = ''.join(norm for _, _, norm in files)
    locale = (ETS / 'service/localization/ZhCN.ets').read_text() \
        + (ETS / 'service/localization/EnUS.ets').read_text()
    findings = []
    for script in sorted(SCRIPTS.glob('device_*.sh')):
        content = script.read_text()
        for m in ASSERT_LOG.finditer(content):
            tag = m.group(2).split(':')[0].strip()
            frag = message_fragment(m.group(2))
            if not tag:
                continue
            words = frag.split()
            if tag in SHARED_LOG_TAGS:
                owner_rel = SHARED_LOG_TAGS[tag]
                owner = next((norm for rel, _, norm in files if rel == owner_rel), '')
                # 页面名是调用方传参（写在各路由注册处），共享日志器里只找「日志正文关键词」
                if not (words and any(w in owner for w in words)):
                    findings.append(f'{script.name}: 断言「{m.group(1)}」的日志正文在共享日志器 '
                                    f'{owner_rel} 里找不到（关键词：{words}）')
                continue
            # TAG 必须与日志关键词在**同一个文件**里（只查全局会漏：旧 TAG 常见于其它文件）
            owners = [rel for rel, _, norm in files if words and all(w in norm for w in words)]
            if owners and not any(("'" + tag + "'") in norm for rel, _, norm in files if rel in owners):
                findings.append(f'{script.name}: 断言「{m.group(1)}」期望日志 TAG "{tag}"，'
                                f'但打这条日志的文件里找不到该 TAG（{", ".join(owners)}）')
            elif not owners and tag not in code:
                findings.append(f'{script.name}: 断言「{m.group(1)}」期望日志 TAG "{tag}"，代码里找不到')
        for m in ASSERT_UI.finditer(content):
            text = m.group(2).strip()
            if text and text not in code and text not in locale:
                findings.append(f'{script.name}: 断言「{m.group(1)}」期望界面文案「{text}」，代码/词条里找不到')
    print('\n'.join(findings) if findings else 'device script assertions all match current code')
    print('total', len(findings))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
