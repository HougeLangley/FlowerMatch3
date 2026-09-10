#!/usr/bin/env python3
"""鲜花消消乐素材生成 v2：渐变双层花瓣 + 柔影 + 超采样抗锯齿。"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 768          # 4x 超采样画布
FINAL = 192      # 输出尺寸
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(BASE, "assets", "flowers")


def petal_layer(cx, cy, dist, rx, ry, tip_color, base_color):
    """画一片朝上的渐变花瓣（尖端在上），返回 RGBA 图层。"""
    top, bottom = cy - dist - ry, cy - dist + ry
    h = max(bottom - top, 1)
    yy, xx = np.mgrid[0:S, 0:S]
    d = ((xx - cx) / rx) ** 2 + ((yy - (cy - dist)) / ry) ** 2
    alpha = np.clip((1.0 - d) * rx * 0.9, 0, 1)
    t = np.clip((yy - top) / h, 0, 1)[..., None]
    rgb = (np.array(tip_color) * (1 - t) + np.array(base_color) * t)
    return Image.fromarray(np.dstack([rgb, alpha[..., None] * 255]).astype(np.uint8), "RGBA")


def center_layer(cx, cy, r, light_color, dark_color, highlight=True):
    """花心：径向渐变 + 高光。"""
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    alpha = np.clip((1.0 - d) * r * 0.5, 0, 1)
    t = np.clip(d, 0, 1)[..., None]
    rgb = np.array(light_color) * (1 - t) + np.array(dark_color) * t
    img = Image.fromarray(np.dstack([rgb, alpha[..., None] * 255]).astype(np.uint8), "RGBA")
    if not highlight:
        return img
    # 高光点
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse(
        [cx - r * 0.55, cy - r * 0.62, cx - r * 0.05, cy - r * 0.12],
        fill=(255, 255, 255, 150))
    img.alpha_composite(hl.filter(ImageFilter.GaussianBlur(6)))
    return img


def shadow_layer(cx, cy, rx, ry, dy, alpha=70, blur=18):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - rx, cy + dy - ry, cx + rx, cy + dy + ry],
                               fill=(20, 30, 20, alpha))
    return sh.filter(ImageFilter.GaussianBlur(blur))


def make_flower(spec):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    img.alpha_composite(shadow_layer(cx, cy, spec["shadow_rx"], 34, S * 0.30))
    for ring in (spec["outer"], spec["inner"]):
        for i in range(ring["n"]):
            ang = 360.0 * i / ring["n"] + ring.get("offset", 0.0)
            layer = petal_layer(cx, cy, ring["dist"], ring["rx"], ring["ry"],
                                ring["tip"], ring["base"])
            img.alpha_composite(layer.rotate(-ang, resample=Image.BICUBIC,
                                             center=(cx, cy)))
    c = spec["center"]
    img.alpha_composite(center_layer(cx, cy, c["r"], c["light"], c["dark"]))
    if "stamens" in spec:
        d = ImageDraw.Draw(img)
        st = spec["stamens"]
        for i in range(st["n"]):
            a = 2 * np.pi * i / st["n"]
            px, py = cx + np.cos(a) * st["dist"], cy + np.sin(a) * st["dist"]
            d.ellipse([px - st["r"], py - st["r"], px + st["r"], py + st["r"]],
                      fill=st["color"])
    return img.resize((FINAL, FINAL), Image.LANCZOS)


FLOWERS = {
    # 玫瑰：深红尖 → 浅红基
    "rose": dict(shadow_rx=200,
                 outer=dict(n=7, rx=95, ry=150, dist=170, tip=(183, 28, 28), base=(229, 115, 115)),
                 inner=dict(n=7, rx=70, ry=105, dist=120, tip=(198, 40, 40), base=(239, 154, 154), offset=25.7),
                 center=dict(r=40, light=(255, 224, 130), dark=(245, 180, 60)),
                 stamens=dict(n=8, dist=52, r=9, color=(194, 120, 30))),
    # 向日葵：多而细的金瓣 + 种子盘
    "sunflower": dict(shadow_rx=210,
                      outer=dict(n=14, rx=44, ry=170, dist=180, tip=(251, 176, 45), base=(255, 236, 120)),
                      inner=dict(n=14, rx=34, ry=120, dist=130, tip=(251, 193, 60), base=(255, 244, 150), offset=12.9),
                      center=dict(r=95, light=(121, 85, 72), dark=(62, 39, 35)),
                      stamens=dict(n=16, dist=60, r=8, color=(93, 58, 50))),
    # 樱花：柔粉 5 瓣
    "sakura": dict(shadow_rx=190,
                   outer=dict(n=5, rx=112, ry=142, dist=150, tip=(236, 90, 140), base=(252, 224, 233)),
                   inner=dict(n=5, rx=80, ry=98, dist=104, tip=(242, 120, 162), base=(255, 240, 245), offset=36.0),
                   center=dict(r=42, light=(255, 238, 170), dark=(245, 190, 90)),
                   stamens=dict(n=6, dist=58, r=8, color=(255, 245, 200))),
    # 郁金香：暖橙
    "tulip": dict(shadow_rx=195,
                  outer=dict(n=6, rx=92, ry=152, dist=165, tip=(230, 74, 25), base=(255, 171, 64)),
                  inner=dict(n=6, rx=66, ry=108, dist=115, tip=(240, 98, 40), base=(255, 190, 100), offset=30.0),
                  center=dict(r=36, light=(255, 245, 190), dark=(250, 210, 110))),
    # 薰衣草：优雅紫
    "lavender": dict(shadow_rx=185,
                     outer=dict(n=8, rx=70, ry=150, dist=162, tip=(94, 53, 177), base=(179, 157, 219)),
                     inner=dict(n=8, rx=52, ry=104, dist=112, tip=(106, 61, 194), base=(209, 196, 233), offset=22.5),
                     center=dict(r=36, light=(230, 222, 245), dark=(160, 130, 210)),
                     stamens=dict(n=6, dist=48, r=8, color=(94, 53, 177))),
    # 百合：白瓣青尖
    "lily": dict(shadow_rx=195,
                 outer=dict(n=6, rx=86, ry=155, dist=165, tip=(162, 214, 240), base=(255, 255, 255)),
                 inner=dict(n=6, rx=62, ry=110, dist=115, tip=(190, 228, 248), base=(255, 255, 255), offset=30.0),
                 center=dict(r=38, light=(255, 228, 130), dark=(245, 185, 70)),
                 stamens=dict(n=6, dist=54, r=8, color=(161, 110, 40))),
}


def gen_background():
    """象牙白 → 鼠尾草绿竖向渐变 + 棋盘区柔光 + 轻晕影。"""
    w, h = 720, 1680
    yy, xx = np.mgrid[0:h, 0:w]
    ty = (yy / (h - 1))[..., None]
    arr = np.array((253, 250, 240)) * (1 - ty) + np.array((224, 237, 212)) * ty
    glow = np.clip(1 - np.sqrt((xx - 360) ** 2 + (yy - 760) ** 2) / 520, 0, 1) ** 2 * 26
    arr += glow[..., None]
    vig = np.clip(np.sqrt(((xx - 360) / 360) ** 2 + ((yy - 840) / 840) ** 2) - 0.62, 0, 1) * 22
    arr -= vig[..., None]
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(
        os.path.join(BASE, "assets", "bg.png"))
    print("  bg.png saved")


def gen_panel(board_w=700, board_h=900):
    """棋盘卡片：白色半透明圆角 + 柔和投影。卡片随棋盘尺寸参数化。"""
    pad, blur_pad = 8, 20
    card_w, card_h = board_w + pad * 2, board_h + pad * 2
    w, h = card_w + blur_pad * 2, card_h + blur_pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [blur_pad, blur_pad + 6, blur_pad + card_w, blur_pad + card_h + 6],
        radius=40, fill=(30, 50, 30, 55))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    ImageDraw.Draw(img).rounded_rectangle(
        [blur_pad, blur_pad, blur_pad + card_w, blur_pad + card_h],
        radius=40, fill=(255, 255, 255, 232))
    img.save(os.path.join(BASE, "assets", "panel.png"))
    print(f"  panel.png saved ({w}x{h})")


def gen_icon(sakura_spec):
    icon = Image.new("RGBA", (FINAL, FINAL), (0, 0, 0, 0))
    ImageDraw.Draw(icon).rounded_rectangle([0, 0, FINAL - 1, FINAL - 1], radius=40,
                                           fill=(67, 122, 78))
    flower = make_flower(sakura_spec).resize((168, 168), Image.LANCZOS)
    icon.alpha_composite(flower, (12, 6))
    icon.save(os.path.join(BASE, "icon.png"))
    print("  icon.png saved")


def gen_magic():
    """魔力花：彩虹渐变花瓣。"""
    import colorsys
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    img.alpha_composite(shadow_layer(cx, cy, 200, 34, S * 0.30))
    n = 8
    for i in range(n):
        tip = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(i / n, 0.85, 0.95))
        base = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(i / n, 0.45, 1.0))
        layer = petal_layer(cx, cy, 165, 88, 150, tip, base)
        img.alpha_composite(layer.rotate(-(360.0 * i / n), resample=Image.BICUBIC,
                                         center=(cx, cy)))
    img.alpha_composite(center_layer(cx, cy, 55, (255, 255, 255), (255, 220, 120)))
    make_out = img.resize((FINAL, FINAL), Image.LANCZOS)
    make_out.save(os.path.join(OUT, "magic.png"))
    print("  magic.png saved")


def gen_badge():
    """行列消除徽章：发光白环 + 左右箭头（竖排版旋转 90° 复用）。"""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    r = 300
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - r, cy - r, cx + r, cy + r],
                                 outline=(255, 255, 255, 160), width=30)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(16)))
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 240), width=22)
    for sign in (-1, 1):  # 左右双箭头
        ax = cx + sign * 150
        d.polygon([(ax + sign * 70, cy), (ax - sign * 20, cy - 60),
                   (ax - sign * 20, cy + 60)], fill=(255, 255, 255, 240))
    img.resize((FINAL, FINAL), Image.LANCZOS).save(
        os.path.join(BASE, "assets", "badge.png"))
    print("  badge.png saved")


def gen_petal_particle():
    """消除特效用的小花瓣粒子（64x64 白色，运行时用 modulate 染色）。"""
    size = 256
    yy, xx = np.mgrid[0:size, 0:size]
    d = ((xx - size / 2) / 70) ** 2 + ((yy - size / 2) / 110) ** 2
    alpha = np.clip((1.0 - d) * 10, 0, 1)
    rgb = np.full((size, size, 3), 255)
    img = Image.fromarray(np.dstack([rgb, alpha[..., None] * 255]).astype(np.uint8), "RGBA")
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(BASE, "assets", "petal.png"))
    print("  petal.png saved")


def gen_bomb_flower():
    """爆炸花（绣球烟花球）：金白相间窄瓣 + 亮白花心 + 火花。"""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    img.alpha_composite(shadow_layer(cx, cy, 190, 34, S * 0.30))
    for i in range(16):
        gold = i % 2 == 0
        tip = (255, 190, 60) if gold else (255, 245, 220)
        base = (255, 150, 30) if gold else (255, 228, 180)
        layer = petal_layer(cx, cy, 158, 40, 135, tip, base)
        img.alpha_composite(layer.rotate(-(360.0 * i / 16), resample=Image.BICUBIC,
                                         center=(cx, cy)))
    img.alpha_composite(center_layer(cx, cy, 70, (255, 255, 245), (255, 200, 80)))
    # 火花：四个方向的钻石小星
    d = ImageDraw.Draw(img)
    for a in (45, 135, 225, 315):
        rad = np.radians(a)
        sx, sy = cx + np.cos(rad) * 250, cy + np.sin(rad) * 250
        r1, r2 = 34, 10
        d.polygon([(sx, sy - r1), (sx + r2, sy), (sx, sy + r1), (sx - r2, sy)],
                  fill=(255, 255, 255, 235))
    img.resize((FINAL, FINAL), Image.LANCZOS).save(os.path.join(OUT, "bomb.png"))
    print("  bomb.png saved")


def gen_star(name, fill, outline):
    """五角星（评级用）。"""
    size = 192
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx = cy = size / 2
    pts = []
    for i in range(10):
        r = 80 if i % 2 == 0 else 36
        a = -np.pi / 2 + i * np.pi / 5
        pts.append((cx + np.cos(a) * r, cy + np.sin(a) * r))
    d = ImageDraw.Draw(img)
    d.polygon(pts, fill=fill, outline=outline)
    img.save(os.path.join(BASE, "assets", name))
    print(f"  {name} saved")


def gen_petal_button(name, petal_tip, petal_base, center_light, center_dark):
    """花瓣形选关按钮：8 柔瓣 + 奶油花心（数字显示区）。输出 340x340。"""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = S / 2
    img.alpha_composite(shadow_layer(cx, cy, 230, 40, S * 0.28, alpha=55, blur=22))
    for i in range(8):
        layer = petal_layer(cx, cy, 195, 120, 185, petal_tip, petal_base)
        img.alpha_composite(layer.rotate(-(360.0 * i / 8), resample=Image.BICUBIC,
                                         center=(cx, cy)))
    img.alpha_composite(center_layer(cx, cy, 135, center_light, center_dark,
                                     highlight=False))
    img.resize((340, 340), Image.LANCZOS).save(os.path.join(BASE, "assets", name))
    print(f"  {name} saved")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, spec in FLOWERS.items():
        make_flower(spec).save(os.path.join(OUT, f"{name}.png"))
        print(f"  {name}.png saved")
    gen_magic()
    gen_badge()
    gen_petal_particle()
    gen_bomb_flower()
    gen_star("star_gold.png", (255, 200, 40), (218, 155, 20))
    gen_star("star_gray.png", (200, 205, 200), (170, 175, 170))
    # 花瓣按钮三态
    gen_petal_button("petal_btn_normal.png",
                     (252, 160, 195), (255, 226, 236), (255, 246, 218), (255, 226, 165))
    gen_petal_button("petal_btn_pressed.png",
                     (238, 130, 170), (250, 200, 218), (250, 238, 205), (245, 215, 150))
    gen_petal_button("petal_btn_disabled.png",
                     (200, 205, 205), (222, 226, 222), (236, 238, 236), (222, 226, 224))
    gen_background()
    gen_panel(board_w=700, board_h=1100)  # 7 列 x 11 行 x 100px
    # icon.png 由 MiniMax 图像模型生成，不再程序化覆盖


if __name__ == "__main__":
    main()
