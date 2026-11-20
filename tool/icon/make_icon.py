import sys, os
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
S = 1728  # 108dp * 16 (supersampled canvas)
u = S / 108.0  # 1dp

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(len(a)))

def gradient(size, c1, c2, diag=True):
    w, h = size
    g = Image.new('RGBA', size)
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = ((x + y) / (w + h)) if diag else y / h
            px[x, y] = lerp(c1, c2, t) + (255,)
    return g

def background():
    small = gradient((216, 216), (52, 55, 74), (18, 19, 27))
    return small.resize((S, S), Image.BICUBIC)

def rr(d, box, r, fill): d.rounded_rectangle([round(v) for v in box], radius=round(r), fill=fill)

def foreground(mono=False):
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cx, cy = S/2, S/2
    # --- バーベル（オレンジのグラデーション）---
    mask = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(mask)
    by = cy - 9*u
    rr(d, (cx-27*u, by-1.6*u, cx+27*u, by+1.6*u), 1.6*u, 255)          # バー
    for sgn in (-1, 1):
        x0 = cx + sgn*13*u
        rr(d, (x0-2.6*u if sgn<0 else x0-0.0*u, by-12*u, x0+0.0*u if sgn<0 else x0+2.6*u, by+12*u), 1.3*u, 255)  # 内側カラー
        xi = cx + sgn*15.5*u
        rr(d, (min(xi, xi+sgn*4.6*u), by-11*u, max(xi, xi+sgn*4.6*u), by+11*u), 2*u, 255)  # 大プレート
        xo = cx + sgn*21*u
        rr(d, (min(xo, xo+sgn*3.6*u), by-7.5*u, max(xo, xo+sgn*3.6*u), by+7.5*u), 1.6*u, 255)  # 小プレート
    color = Image.new('RGBA', (S, S), (255, 255, 255, 255)) if mono else \
        gradient((216, 216), (255, 160, 70), (240, 70, 30)).resize((S, S), Image.BICUBIC)
    fg.paste(color, (0, 0), mask)
    # --- メモの行（白）---
    d2 = ImageDraw.Draw(fg)
    white = (255, 255, 255, 255)
    soft = (255, 255, 255, 255) if mono else (255, 255, 255, 150)
    y = cy + 9*u
    rr(d2, (cx-22*u, y-1.7*u, cx+22*u, y+1.7*u), 1.7*u, white)
    y += 8*u
    rr(d2, (cx-22*u, y-1.7*u, cx+10*u, y+1.7*u), 1.7*u, soft)
    # 行末の「@」っぽいアクセント（小さな円）
    if not mono:
        r = 2.3*u
        d2.ellipse([cx+15.5*u-r, y-r, cx+15.5*u+r, y+r], fill=(255, 140, 60, 255))
    return fg

def shadowed(fg):
    a = fg.split()[3].filter(ImageFilter.GaussianBlur(1.5*u))
    sh = Image.new('RGBA', fg.size, (0, 0, 0, 0))
    sh.putalpha(a.point(lambda v: int(v*0.45)))
    out = Image.new('RGBA', fg.size, (0, 0, 0, 0))
    out.alpha_composite(sh, (0, round(1.2*u)))
    out.alpha_composite(fg)
    return out

bg = background()
fg = shadowed(foreground())
mono = foreground(mono=True)

res = os.path.join(OUT, 'res')
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, f in dens.items():
    dd = os.path.join(res, f'mipmap-{name}'); os.makedirs(dd, exist_ok=True)
    n = round(108*f)
    bg.resize((n, n), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_background.png'))
    fg.resize((n, n), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_foreground.png'))
    mono.resize((n, n), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_monochrome.png'))
    # 旧端末用（角丸の正方形、48dp）
    full = bg.copy(); full.alpha_composite(fg)
    crop = full.crop((round(18*u*0.55), round(18*u*0.55), S-round(18*u*0.55), S-round(18*u*0.55)))
    m = Image.new('L', crop.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, crop.size[0]-1, crop.size[1]-1], radius=crop.size[0]*0.22, fill=255)
    crop.putalpha(m)
    crop.resize((round(48*f), round(48*f)), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher.png'))

# プレビュー（円形マスク・角丸マスク）
full = bg.copy(); full.alpha_composite(fg)
inner = full.crop((round(18*u), round(18*u), S-round(18*u), S-round(18*u))).resize((432, 432), Image.LANCZOS)
prev = Image.new('RGBA', (1000, 480), (235, 235, 240, 255))
for i, shape in enumerate(['circle', 'squircle']):
    m = Image.new('L', (432, 432), 0); dm = ImageDraw.Draw(m)
    if shape == 'circle': dm.ellipse([0, 0, 431, 431], fill=255)
    else: dm.rounded_rectangle([0, 0, 431, 431], radius=110, fill=255)
    prev.paste(inner, (24 + i*500, 24), m)
prev.save(os.path.join(OUT, 'preview.png'))
