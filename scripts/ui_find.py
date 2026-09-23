"""在 uitest 的界面树里按文案定位节点，输出中心坐标 "x y"。

单独成文件而不是内联在 shell 里，是为了让 ui.sh 保持可读（内联 python 的缩进
在 bash heredoc 里很容易出错）。

用法：python3 ui_find.py <文案> <layout.json>
退出码：找不到节点返回 1。
"""
import json
import sys


def center(bounds):
    left, rest = bounds[1:].split(',', 1)
    top, rest = rest.split(']', 1)
    right, bottom = rest[1:-1].split(',')
    return int((int(left) + int(right)) / 2), int((int(top) + int(bottom)) / 2)


def collect(node, target, out):
    attrs = node.get('attributes', {})
    text = (attrs.get('text') or '').strip()
    if text == target:
        out.append(attrs.get('bounds', ''))
    for child in node.get('children') or []:
        collect(child, target, out)


def main():
    target = sys.argv[1]
    data = json.load(open(sys.argv[2]))
    hits = []
    collect(data, target, hits)
    if not hits:
        sys.exit(1)
    x, y = center(hits[0])
    print(x, y)


main()
