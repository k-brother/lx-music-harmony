#!/usr/bin/env python3
"""LX Music 鸿蒙版 · 桌面图标生成器（品牌标重绘版）

保留 LX Music 的品牌标（音符 + 下载箭头），只把工艺做细：

  background.png  深色底：斜向炭黑渐变 + 品牌绿柔光 + 顶部极淡高光
                  （不用整块绿底：那样既不品牌也不耐看）
  foreground.png  品牌标：音符浅绿、箭头深绿、柔和投影，高度占画布 56%（安全区内）

品牌标路径直接取自 Android 端
`android/app/src/main/res/drawable/ic_launcher_foreground.xml`，
所以两端是同一个标，不存在「鸿蒙版另画一个」的口径漂移。

依赖：仅 Pillow —— 文件里自带极简 SVG 路径采样器（M/C/c/L/H/V/Z + 贝塞尔细分），
不依赖任何 SVG 渲染库，任何机器上重跑都能得到同一张图。

用法：python3 scripts/gen_app_icon.py
"""
import os
import re
from PIL import Image, ImageDraw, ImageFilter

OUT = 1024
SS = 4
S = OUT * SS

# ---- 品牌色（与 Android 端 ic_launcher_foreground.xml 一致）----
NOTE_TOP = (118, 226, 172)     # 音符顶部（更亮）
NOTE_BOTTOM = (78, 196, 140)   # 音符底部
ARROW_TOP = (88, 186, 138)     # 箭头顶部
ARROW_BOTTOM = (64, 158, 114)  # 箭头底部

BG_LIGHT = (52, 59, 68)        # 深色底（左上，留一点提亮，深色壁纸上不会糊成一片）
BG_DARK = (9, 11, 14)          # 深色底（右下）

MARK_HEIGHT_RATIO = 0.56       # 品牌标高度占画布比例（留出安全边距）
MARK_BASELINE_SHIFT = -0.004   # 视觉重心微调（相对画布，正数下移）

# 品牌标矢量路径（viewBox 447.94×447.94，与安卓端一致）
VIEWBOX = 447.94
LOGO_TRANSFORM = (0.48, 116.4644, 116.4644)  # scale, translateX, translateY
NOTE_PATH = ("M203.81,0.48c-19.67,-3.35 -35.76,11.14 -35.76,31.09v206.17c-11.64,-4.27 "
             "-24.17,-6.72 -37.28,-6.72c-59.9,0 -108.47,48.57 -108.47,108.47c0,59.9 48.56,108.46 "
             "108.47,108.46c34.14,0 64.54,-15.82 84.41,-40.48l-49.66,-49.66c-15.12,-15.11 "
             "-11.71,-28.9 -9.54,-34.14c2.17,-5.23 9.51,-17.4 30.88,-17.4h18.08v-56.88c0,-21.13 "
             "14.62,-38.86 34.27,-43.74c0.03,-44.37 0.03,-81.81 0.03,-81.81c140.15,0 131.72,83.97 "
             "115.32,132.2c-6.42,18.88 -2.6,22.05 10.89,7.35C536.47,77.11 298.38,16.57 203.81,0.48z")
ARROW_PATH = ("M301.06,223.88h-50.99c-3.91,0 -7.57,0.95 -10.89,2.52c-8.62,4.09 -14.61,12.8 "
              "-14.61,22.97v76.51h-37.71c-14.08,0 -17.43,8.07 -7.47,18.03l46.89,46.9l31.25,31.25c4.98,4.99 "
              "11.51,7.47 18.03,7.47c6.52,0 13.05,-2.48 18.03,-7.47l78.15,-78.14c9.95,-9.96 6.61,-18.03 "
              "-7.47,-18.03h-37.71v-76.51C326.57,235.29 315.15,223.88 301.06,223.88z")

NUM = re.compile(r'-?\d*\.?\d+(?:e-?\d+)?')


def _tokens(path):
    pos = 0
    out = []
    while pos < len(path):
        ch = path[pos]
        if ch.isalpha():
            out.append(ch)
            pos += 1
            if pos < len(path) and path[pos].isalpha():
                continue
        else:
            m = NUM.match(path, pos)
            if not m:
                pos += 1
                continue
            out.append(float(m.group()))
            pos = m.end()
    return out


def _cubic(p0, p1, p2, p3, steps=24):
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        x = u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0]
        y = u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]
        pts.append((x, y))
    return pts


def path_points(path, scale, dx, dy):
    """极简 SVG 路径采样（够用即可）：M/m c v l h z（含多段参数）。"""
    tk = _tokens(path)
    i = 0
    cx = cy = 0.0
    sx = sy = 0.0
    cmd = None
    pts = []
    while i < len(tk):
        if isinstance(tk[i], str):
            cmd = tk[i]
            i += 1
            if cmd in 'zZ':
                pts.append((sx, sy))
                cx, cy = sx, sy
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == 'M':
            x, y = tk[i], tk[i + 1]
            i += 2
            cx, cy = (cx + x, cy + y) if rel else (x, y)
            sx, sy = cx, cy
            pts.append((cx, cy))
        elif c == 'C':
            x1, y1, x2, y2, x3, y3 = tk[i:i + 6]
            i += 6
            if rel:
                p1 = (cx + x1, cy + y1)
                p2 = (cx + x2, cy + y2)
                p3 = (cx + x3, cy + y3)
            else:
                p1, p2, p3 = (x1, y1), (x2, y2), (x3, y3)
            pts.extend(_cubic((cx, cy), p1, p2, p3))
            cx, cy = p3
        elif c == 'L':
            x, y = tk[i], tk[i + 1]
            i += 2
            cx, cy = (cx + x, cy + y) if rel else (x, y)
            pts.append((cx, cy))
        elif c == 'H':
            x = tk[i]
            i += 1
            cx = cx + x if rel else x
            pts.append((cx, cy))
        elif c == 'V':
            y = tk[i]
            i += 1
            cy = cy + y if rel else y
            pts.append((cx, cy))
        else:
            i += 1
    scale_all, tx, ty = LOGO_TRANSFORM
    return [((x * scale_all + tx) * scale + dx, (y * scale_all + ty) * scale + dy) for x, y in pts]


def path_mask(path, size, scale, dx, dy):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).polygon(path_points(path, scale, dx, dy), fill=255)
    return m


def gradient(size, top, bottom, box):
    g = Image.new('L', (size, size))
    px = g.load()
    y0, y1 = box
    for y in range(size):
        t = 0.0 if y1 <= y0 else (y - y0) / (y1 - y0)
        t = min(max(t, 0.0), 1.0)
        px_row = int(round(255 * t))
        for x in range(size):
            px[x, y] = px_row
    tinted = Image.new('RGB', (size, size))
    tp = tinted.load()
    for y in range(size):
        t = px[0, y] / 255.0
        c = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3))
        for x in range(size):
            tp[x, y] = c
    return tinted


def radial_shadow(size, mask, blur, dy, color, alpha):
    sh = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sh.paste(color + (alpha,), (0, 0), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    return sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -dy))


def make_background():
    from PIL import Image as I
    bg = gradient(OUT, BG_LIGHT, BG_DARK, (0, OUT)).convert('RGBA')
    glow = I.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
    m = I.new('L', (OUT, OUT), 0)
    d = ImageDraw.Draw(m)
    cx, cy, r = OUT * 0.52, OUT * 0.55, OUT * 0.62
    steps = 90
    for i in range(steps, 0, -1):
        t = i / steps
        d.ellipse([cx - r * t, cy - r * t, cx + r * t, cy + r * t],
                  fill=int(60 * (1 - t) ** 1.7))
    m = m.filter(ImageFilter.GaussianBlur(OUT * 0.05))
    glow.putalpha(m)
    glow = I.composite(I.new('RGBA', (OUT, OUT), (78, 210, 150, 255)),
                       I.new('RGBA', (OUT, OUT), (0, 0, 0, 0)), m)
    bg = I.alpha_composite(bg, glow)

    # 顶部一层极淡的高光（玻璃感，深色壁纸上图标更有边界）
    sheen = I.new('L', (OUT, OUT), 0)
    sd = ImageDraw.Draw(sheen)
    for y in range(int(OUT * 0.42)):
        t = y / (OUT * 0.42)
        sd.line([(0, y), (OUT, y)], fill=int(16 * (1 - t) ** 1.6))
    sheen = sheen.filter(ImageFilter.GaussianBlur(OUT * 0.01))
    bg = I.alpha_composite(bg, I.composite(I.new('RGBA', (OUT, OUT), (255, 255, 255, 255)),
                                           I.new('RGBA', (OUT, OUT), (0, 0, 0, 0)), sheen))
    return bg.convert('RGB')


def make_foreground():
    tmp_scale = S / VIEWBOX
    dx0 = (S - VIEWBOX * tmp_scale) / 2
    note = path_mask(NOTE_PATH, S, tmp_scale, dx0, dx0)
    arrow = path_mask(ARROW_PATH, S, tmp_scale, dx0, dx0)

    # 合并 → 缩放/居中到目标比例
    mark = Image.new('L', (S, S), 0)
    mark.paste(note, (0, 0), note)
    mark.paste(arrow, (0, 0), arrow)
    bb = mark.getbbox()
    h = bb[3] - bb[1]
    scale = (S * MARK_HEIGHT_RATIO) / h
    resample = Image.LANCZOS
    note = note.resize((int(S * scale), int(S * scale)), resample)
    arrow = arrow.resize((int(S * scale), int(S * scale)), resample)
    mark = mark.resize((int(S * scale), int(S * scale)), resample)

    canvas = Image.new('L', (S, S), 0)
    ox = (S - mark.width) // 2
    oy = (S - mark.height) // 2 + int(S * MARK_BASELINE_SHIFT)
    canvas.paste(mark, (ox, oy))
    note_c = Image.new('L', (S, S), 0)
    note_c.paste(note, (ox, oy))
    arrow_c = Image.new('L', (S, S), 0)
    arrow_c.paste(arrow, (ox, oy))
    mark, note, arrow = canvas, note_c, arrow_c

    bb = mark.getbbox()
    note_img = gradient(S, NOTE_TOP, NOTE_BOTTOM, (bb[1], bb[3])).convert('RGBA')
    arrow_img = gradient(S, ARROW_TOP, ARROW_BOTTOM, (bb[1], bb[3])).convert('RGBA')

    shadow = radial_shadow(S, mark, S * 0.014, int(S * 0.012), (0, 0, 0), 120)

    comp = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    comp = Image.alpha_composite(comp, shadow)
    comp.paste(note_img, (0, 0), note)
    comp.paste(arrow_img, (0, 0), arrow)
    return comp.resize((OUT, OUT), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for t in ('AppScope/resources/base/media', 'entry/src/main/resources/base/media'):
        d = os.path.join(root, t)
        os.makedirs(d, exist_ok=True)
        make_background().save(os.path.join(d, 'background.png'))
        make_foreground().save(os.path.join(d, 'foreground.png'))
        print('written', t)


if __name__ == '__main__':
    main()
