#!/usr/bin/env python3
"""LX Music 鸿蒙版 · 桌面图标生成器

产出 HarmonyOS 分层图标的两层（1024×1024）：
  background.png  品牌绿斜向渐变 + 左上柔光 + 右下压深（系统负责切圆角/遮罩）
  foreground.png  白色回音符（柔和投影），内容收在安全区内

设计要点：
- 品牌色取自默认主题 green（c-primary = rgb(77,175,124)），深浅两端保证在浅色/深色桌面都立得住；
- 造型用「回音符」而不是老版的「音符 + 下载箭头」：后者在 48px 下箭头糊成一团；
- 只用一层柔和阴影表现层次，跟应用内 iOS 风格 token（圆润、克制、无重描边）一致。

用法：python3 scripts/gen_app_icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = 1024        # 输出尺寸
SS = 4            # 超采样倍数（先大后缩，得到干净边缘）
S = OUT * SS

WHITE = (255, 255, 255, 255)
MARK_TOP = (255, 255, 255, 255)
MARK_BOTTOM = (233, 248, 241, 255)
# 音符宽度占画布比例（HarmonyOS 分层图标安全区约 60%，这里留一点余量）
MARK_WIDTH_RATIO = 0.56

# 底色渐变色标（斜向 45°）
STOPS = [(0.0, (108, 220, 164)), (0.45, (63, 175, 124)), (1.0, (36, 132, 95))]


def mix(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def sample(t):
    for i in range(len(STOPS) - 1):
        p0, c0 = STOPS[i]
        p1, c1 = STOPS[i + 1]
        if t <= p1 or i == len(STOPS) - 2:
            local = 1.0 if p1 == p0 else (t - p0) / (p1 - p0)
            return mix(c0, c1, min(max(local, 0.0), 1.0))
    return STOPS[-1][1]


def diagonal_gradient(size):
    """真正 45° 斜向渐变（逐像素按 (x+y) 采样，无旋转裁切产生的硬三角）。"""
    img = Image.new('RGB', (size, size))
    px = img.load()
    denom = 2.0 * (size - 1)
    cache = {}
    for y in range(size):
        row_off = y
        for x in range(size):
            key = ((x + row_off) * 512) // int(denom)
            c = cache.get(key)
            if c is None:
                c = sample(key / 512.0)
                cache[key] = c
            px[x, y] = c
    return img


def radial_mask(size, cx, cy, radius, alpha, power=1.6):
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    steps = int(radius / (size / 220)) + 1
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        a = int(round(255 * alpha * (1 - t) ** power))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=a)
    return m.filter(ImageFilter.GaussianBlur(size * 0.03))


def make_background():
    bg = diagonal_gradient(OUT).convert('RGBA')

    glow = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
    glow.putalpha(radial_mask(OUT, OUT * 0.22, OUT * 0.14, OUT * 0.92, 0.18))
    bg = Image.alpha_composite(bg, Image.new('RGBA', (OUT, OUT), WHITE + (0,)) if False else
                               Image.composite(Image.new('RGBA', (OUT, OUT), WHITE),
                                               Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0)),
                                               glow.getchannel('A')))

    shade = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
    shade.putalpha(radial_mask(OUT, OUT * 0.92, OUT * 0.96, OUT * 0.96, 0.18))
    bg = Image.alpha_composite(bg, Image.composite(Image.new('RGBA', (OUT, OUT), (7, 48, 32, 255)),
                                                  Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0)),
                                                  shade.getchannel('A')))
    return bg.convert('RGB')


def note_shape():
    """白音符（双八分音符 + 符杠）剪影，画在 S×S 透明层上。"""
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    stem_w = 118
    left_x, right_x = 1338, 2432
    stem_top_l, stem_top_r = 1230, 1120
    head_cy = 2680            # 符头中心 y（符干到底端）
    head_rx, head_ry = 232, 168

    # 符杠：一条随符干高度倾斜的圆头带
    beam_w = 152
    p1 = (left_x + stem_w // 2, stem_top_l + 30)
    p2 = (right_x + stem_w // 2, stem_top_r + 30)
    d.line([p1, p2], fill=WHITE, width=beam_w)
    d.ellipse([p1[0] - beam_w // 2, p1[1] - beam_w // 2, p1[0] + beam_w // 2, p1[1] + beam_w // 2], fill=WHITE)
    d.ellipse([p2[0] - beam_w // 2, p2[1] - beam_w // 2, p2[0] + beam_w // 2, p2[1] + beam_w // 2], fill=WHITE)

    # 两条符干
    d.rounded_rectangle([left_x, stem_top_l, left_x + stem_w, head_cy], radius=stem_w // 2, fill=WHITE)
    d.rounded_rectangle([right_x, stem_top_r, right_x + stem_w, head_cy], radius=stem_w // 2, fill=WHITE)

    # 两个符头（倾斜椭圆，贴在符干左下/右侧端点）
    for cx in (left_x + stem_w // 2, right_x + stem_w // 2):
        w, h = head_rx * 2, head_ry * 2
        pad = int(max(w, h) * 0.6)
        tmp = Image.new('RGBA', (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
        ImageDraw.Draw(tmp).ellipse([pad, pad, pad + w, pad + h], fill=WHITE)
        tmp = tmp.rotate(-18, resample=Image.BICUBIC, expand=False)
        layer.alpha_composite(tmp, (cx - w // 2 - pad, head_cy - h // 2 - pad))

    # 按实际包围盒居中（超采样坐标），再进行上色
    bbox = layer.getchannel('A').getbbox()
    if bbox:
        cx = (bbox[0] + bbox[2]) / 2
        cy = (bbox[1] + bbox[3]) / 2
        layer = layer.transform(layer.size, Image.AFFINE,
                                (1, 0, cx - S / 2, 0, 1, cy - S / 2), resample=Image.BICUBIC)

    # 竖向微渐变（顶白 -> 底部略带冷绿），避免死白
    grad = Image.new('RGBA', (S, S))
    gp = grad.load()
    for y in range(S):
        t = y / (S - 1)
        c = mix(MARK_TOP[:3], MARK_BOTTOM[:3], min(1.0, t * 1.15))
        gp_row = c
        for x in range(S):
            gp[x, y] = gp_row + (255,)
    layer = Image.composite(grad, Image.new('RGBA', (S, S), (0, 0, 0, 0)), layer.getchannel('A'))
    return layer


def make_foreground():
    note = note_shape()

    # 统一缩放：各平台对分层图标安全区的要求不同，按比例收口比逐像素调更稳
    bbox = note.getchannel('A').getbbox()
    if bbox:
        scale = (S * MARK_WIDTH_RATIO) / (bbox[2] - bbox[0])
        scaled = note.resize((int(S * scale), int(S * scale)), Image.LANCZOS)
        canvas = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        # 视觉重心略高于几何中心（音符带尾巴，纯居中会显沉）
        canvas.alpha_composite(scaled, ((S - scaled.width) // 2,
                                        (S - scaled.height) // 2 - int(S * 0.012)))
        note = canvas

    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    shadow.paste((3, 40, 26, 92), (0, 0), note.getchannel('A'))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.010))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -int(S * 0.010)))

    comp = Image.alpha_composite(shadow, note)
    return comp.resize((OUT, OUT), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    targets = [
        os.path.join(root, 'AppScope/resources/base/media'),
        os.path.join(root, 'entry/src/main/resources/base/media'),
    ]
    bg = make_background()
    fg = make_foreground()
    for t in targets:
        os.makedirs(t, exist_ok=True)
        bg.save(os.path.join(t, 'background.png'))
        fg.save(os.path.join(t, 'foreground.png'))
        print('written', t)


if __name__ == '__main__':
    main()
