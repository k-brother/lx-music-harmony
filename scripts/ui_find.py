"""在 uitest 的界面树里按文案定位节点，输出中心坐标 "x y"。

单独成文件而不是内联在 shell 里，是为了让 ui.sh 保持可读（内联 python 的缩进
在 bash heredoc 里很容易出错）。

匹配范围：可见文案，以及无障碍/描述类文案（图标按钮没有可见文字，只有
accessibilityText，例如播放页的「更多」）。这样真机脚本可以「先按标签点、
失败再退回坐标」，减少对布局坐标的硬依赖。

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


LABEL_KEYS = ('text', 'description', 'accessibilityText', 'accessibilityDescription', 'hint')


def attribute_map(raw):
    """兼容两种 dumpLayout 形态：{name: value} 与 [{name, value}, ...]"""
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, list):
        out = {}
        for item in raw:
            if isinstance(item, dict) and 'name' in item:
                out[str(item['name'])] = item.get('value')
        return out
    return {}


def collect(node, target, out):
    attrs = attribute_map(node.get('attributes', {}))
    for key in LABEL_KEYS:
        value = attrs.get(key)
        if isinstance(value, str) and value.strip() == target:
            out.append(attrs.get('bounds', ''))
            break
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
