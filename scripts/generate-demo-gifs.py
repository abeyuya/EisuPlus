#!/usr/bin/env python3
"""配布サイトと README に載せる、機能の動きを示す GIF を生成する。

画面の録画ではなく、デスクトップ・ウィンドウ・カーソル・押しているキーを簡略化して描く。
ウィンドウの動きはアプリと同じ規則で計算する (Gesture)。
- 移動: 修飾キーを押した後の最初のマウス移動でウィンドウをつかみ、以降はカーソルと同じだけ動かす
- リサイズ: 左上を固定して、右下の角をカーソルと同じだけ動かす。最小は 120×80
- スナップ: 移動中にカーソルが画面の左右の端から 5pt 以内に入ると半分、上端なら最大化のプレビューを出し、キーを離すと確定する。
  スナップしたままのウィンドウを動かし始めると、カーソルの横の相対位置を保って元のサイズに戻る
- 英数・かな: 左⌘の単押しで英数、右⌘の単押しでかなに切り替わる。切り替わるのはキーを離したとき

既定のキーや挙動を変えたら作り直す。

使い方 (Pillow が必要):
    python3 -m venv /tmp/demo-venv && /tmp/demo-venv/bin/pip install pillow
    /tmp/demo-venv/bin/python scripts/generate-demo-gifs.py site/demo

<名前>.gif と、動きを減らす設定 (prefers-reduced-motion) の人に見せる静止画 <名前>.png を書き出す。
"""
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 600, 375  # 出力の大きさ。サイトのカードに 2 倍の解像度で収まる
S = 2  # 縁を滑らかにするため、S 倍で描いてから縮小する
FPS = 20
COLORS = 256  # GIF のパレットの色数

MENU_BAR = 22
VISIBLE = (0, MENU_BAR, W, H - MENU_BAR)  # メニューバーを除いた範囲 (x, y, w, h)
EDGE = 5  # スナップの端の判定 (SnapController.edgeThreshold)
MIN_SIZE = (120, 80)  # リサイズの最小 (WindowOperator.minimumSize)
TITLE = 28  # タイトルバーの高さ
SHADOW = 20  # ウィンドウの影を描く余白
KEY_H = 32

FONT_UI = "/System/Library/Fonts/SFNS.ttf"  # ⌘⌃⌥ がある (あ はない)
FONT_JA = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"  # あ がある (⌃⌥ はない)
FONT_JA_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# 配色はサイト (site/style.css) に合わせる
# 壁紙を単色にするのは、GIF の少ない色数だとグラデーションに段が付くため
WALLPAPER = (226, 233, 249)
MENU_BG = (247, 248, 251)
MENU_TEXT = (110, 121, 138)
MENU_ITEM = (203, 209, 220)
WINDOW_BG = (255, 255, 255)
TITLE_BG = (241, 243, 247)
WINDOW_BORDER = (208, 214, 224)
SHADOW_COLOR = (30, 42, 59)
LINE = (226, 230, 238)
TEXT = (30, 42, 59)
MUTED = (91, 103, 121)
ACCENT = (47, 107, 255)
ACCENT_DARK = (29, 84, 222)
KEY_BG = (244, 246, 250)
KEY_BORDER = (201, 208, 220)
KEY_SHADOW = (142, 155, 176)
TRAFFIC = ((255, 95, 87), (254, 188, 46), (40, 200, 64))


def px(v):
    return round(v * S)


def box(x, y, w, h):
    return [px(x), px(y), px(x + w) - 1, px(y + h) - 1]


@lru_cache(maxsize=None)
def font(path, size, weight=None):
    f = ImageFont.truetype(path, px(size))
    if weight:
        f.set_variation_by_name(weight)
    return f


def paste(img, sprite, x, y):
    img.paste(sprite, (px(x), px(y)), sprite)


# --- 動き


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return 4 * x**3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def path(*keys):
    """(時刻, x, y[, 曲がり]) の列から、時刻ごとのカーソル位置を返す関数を作る。
    間はなめらかにつなぎ、曲がりが 0 でなければ進行方向の横へふくらませる"""

    def at(t):
        if t <= keys[0][0]:
            return keys[0][1:3]
        for a, b in zip(keys, keys[1:]):
            if t <= b[0]:
                s = ease((t - a[0]) / (b[0] - a[0]))
                dx, dy = b[1] - a[1], b[2] - a[2]
                bend = (b[3] if len(b) > 3 else 0) * 4 * s * (1 - s)
                return (a[1] + dx * s - dy * bend, a[2] + dy * s + dx * bend)
        return keys[-1][1:3]

    return at


def held(*intervals):
    """(押した時刻, 離した時刻) の列から、時刻ごとにキーを押しているかを返す関数を作る"""
    return lambda t: any(t0 <= t < t1 for t0, t1 in intervals)


def snap_zone(mouse):
    """SnapController.zone と同じ判定。角では左右半分を優先する"""
    x, y = mouse
    vx, vy, vw, vh = VISIBLE
    if x <= EDGE:
        return (vx, vy, vw / 2, vh)
    if x >= W - EDGE - 1:
        return (vx + vw / 2, vy, vw / 2, vh)
    if y <= EDGE:
        return VISIBLE
    return None


def unsnap(frame, size, mouse):
    """WindowOperator.unsnapIfNeeded と同じく、カーソルの横の相対位置を保って元のサイズに戻す"""
    x, y, w, h = frame
    ratio = (mouse[0] - x) / w
    offset = mouse[1] - y
    return (mouse[0] - ratio * size[0], y if offset < size[1] else mouse[1] - size[1] / 2, *size)


class Gesture:
    """WindowOperator と同じ規則で、カーソルとキーの状態からウィンドウの位置とサイズを決める"""

    def __init__(self, mode, frame):
        self.mode = mode  # "move" / "resize"
        self.frame = frame  # (x, y, w, h)
        self.pressed = False
        self.grab = None  # つかんだときの (カーソル, ウィンドウ)
        self.last_mouse = None
        self.snapped = None  # スナップしたままなら (スナップ後の frame, 元のサイズ)
        self.zone = None  # プレビュー中のスナップ先

    def step(self, mouse, pressed):
        if not pressed and self.pressed:
            # キーを離したらスナップを確定する
            if self.zone and self.grab:
                self.snapped = (self.zone, self.grab[1][2:])
                self.frame = self.zone
            self.grab = None
            self.zone = None
        self.pressed = pressed
        moved = mouse != self.last_mouse
        self.last_mouse = mouse
        if not pressed or not moved:
            return

        if self.grab is None:
            if self.mode == "move" and self.snapped:
                snapped_frame, size = self.snapped
                self.snapped = None
                if snapped_frame == self.frame:
                    self.frame = unsnap(self.frame, size, mouse)
            self.grab = (mouse, self.frame)
            return

        (mx, my), (x, y, w, h) = self.grab
        dx, dy = mouse[0] - mx, mouse[1] - my
        if self.mode == "move":
            # macOS はウィンドウをメニューバーより上に置かない
            self.frame = (x + dx, max(y + dy, MENU_BAR), w, h)
            self.zone = snap_zone(mouse)
        else:
            self.frame = (x, y, max(w + dx, MIN_SIZE[0]), max(h + dy, MIN_SIZE[1]))


# --- 描画


@lru_cache(maxsize=None)
def wallpaper():
    return Image.new("RGB", (px(W), px(H)), WALLPAPER)


@lru_cache(maxsize=None)
def menu_bar(indicator=None):
    img = Image.new("RGBA", (px(W), px(MENU_BAR)), MENU_BG + (255,))
    d = ImageDraw.Draw(img)
    d.line([(0, px(MENU_BAR) - 1), (px(W), px(MENU_BAR) - 1)], fill=WINDOW_BORDER, width=S)
    # 左はアプリのメニュー、右はステータス項目の代わりの棒
    x = 16
    for i, w in enumerate((30, 22, 26, 20)):
        d.rounded_rectangle(box(x, 8, w, 6), radius=px(3), fill=MENU_TEXT if i == 0 else MENU_ITEM)
        x += w + 14
    x = W - 16
    for w in (46, 16, 16):
        x -= w
        d.rounded_rectangle(box(x, 8, w, 6), radius=px(3), fill=MENU_ITEM)
        x -= 14
    if indicator:
        # 入力ソースのメニュー
        d.rounded_rectangle(box(x - 20, 3, 20, 16), radius=px(4), fill=TEXT)
        d.text((px(x - 10), px(11)), indicator, font=font(FONT_JA_BOLD, 11), fill=(255, 255, 255), anchor="mm")
    return img


@lru_cache(maxsize=256)
def window_sprite(w, h, lines):
    size = (px(w + SHADOW * 2), px(h + SHADOW * 2))
    shadow = Image.new("L", size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle(box(SHADOW, SHADOW + 5, w, h), radius=px(10), fill=64)
    img = Image.new("RGBA", size, SHADOW_COLOR + (0,))
    img.putalpha(shadow.filter(ImageFilter.GaussianBlur(px(9))))

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0 = y0 = SHADOW
    d.rounded_rectangle(box(x0, y0, w, h), radius=px(10), fill=WINDOW_BG)
    d.rounded_rectangle(box(x0, y0, w, TITLE), radius=px(10), fill=TITLE_BG, corners=(True, True, False, False))
    d.line([(px(x0), px(y0 + TITLE)), (px(x0 + w) - 1, px(y0 + TITLE))], fill=WINDOW_BORDER, width=S)
    for i, color in enumerate(TRAFFIC):
        cx, cy = x0 + 16 + i * 20, y0 + TITLE / 2
        d.ellipse([px(cx - 6), px(cy - 6), px(cx + 6), px(cy + 6)], fill=color)
    if lines:
        # 文書の行の代わりの棒
        widths = (0.86, 0.62, 0.92, 0.48, 0.78, 0.66, 0.9, 0.55)
        y, i = y0 + TITLE + 18, 0
        while y + 7 <= y0 + h - 16:
            d.rounded_rectangle(box(x0 + 20, y, (w - 40) * widths[i % len(widths)], 7), radius=px(3.5), fill=LINE)
            y, i = y + 19, i + 1
    d.rounded_rectangle(box(x0, y0, w, h), radius=px(10), outline=WINDOW_BORDER, width=S)
    img.alpha_composite(layer)
    return img


def draw_window(img, frame, lines=True):
    x, y, w, h = frame
    # 大きさが少しずつ変わるリサイズ中も使い回せるよう、描く単位に丸める
    sprite = window_sprite(round(w * S) / S, round(h * S) / S, lines)
    paste(img, sprite, x - SHADOW, y - SHADOW)


@lru_cache(maxsize=None)
def preview_sprite(w, h):
    # SnapPreviewWindow と同じく、スナップ先から 4pt 内側に、アクセントカラーの 20% で塗り 80% で縁取る
    w, h = w - 8, h - 8
    img = Image.new("RGBA", (px(w), px(h)), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        box(0, 0, w, h), radius=px(10), fill=ACCENT + (51,), outline=ACCENT + (204,), width=px(2)
    )
    return img


CURSOR_PAD = 3


@lru_cache(maxsize=None)
def cursor_sprite():
    points = [(0, 0), (0, 16.5), (3.9, 12.8), (6.6, 19.1), (9.3, 18.0), (6.7, 11.9), (11.9, 11.9)]
    size = (px(18), px(26))

    def polygon(dx, dy):
        return [(px(x + CURSOR_PAD + dx), px(y + CURSOR_PAD + dy)) for x, y in points]

    shadow = Image.new("L", size, 0)
    ImageDraw.Draw(shadow).polygon(polygon(0, 1), fill=90)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.putalpha(shadow.filter(ImageFilter.GaussianBlur(px(1))))
    ImageDraw.Draw(img).polygon(polygon(0, 0), fill=(0, 0, 0, 255), outline=(255, 255, 255, 255), width=px(1.3))
    return img


def draw_cursor(img, mouse):
    paste(img, cursor_sprite(), mouse[0] - CURSOR_PAD, mouse[1] - CURSOR_PAD)


def draw_key(img, x, y, w, symbol, name, pressed):
    """サイトの <kbd> と同じ見た目のキー。押している間はアクセントカラーにして少し沈める"""
    d = ImageDraw.Draw(img)
    drop = 1.5 if pressed else 0
    d.rounded_rectangle(box(x, y + 2.5, w, KEY_H), radius=px(7), fill=ACCENT_DARK if pressed else KEY_SHADOW)
    d.rounded_rectangle(
        box(x, y + drop, w, KEY_H),
        radius=px(7),
        fill=ACCENT if pressed else KEY_BG,
        outline=ACCENT_DARK if pressed else KEY_BORDER,
        width=S,
    )
    if not symbol:
        return
    color = (255, 255, 255) if pressed else TEXT
    symbol_font, name_font = font(FONT_UI, 15, "Semibold"), font(FONT_UI, 11.5, "Medium")
    gap = px(5)
    width = symbol_font.getlength(symbol) + gap + name_font.getlength(name)
    tx, cy = px(x + w / 2) - width / 2, px(y + drop + KEY_H / 2)
    d.text((tx, cy), symbol, font=symbol_font, fill=color, anchor="lm")
    d.text((tx + symbol_font.getlength(symbol) + gap, cy), name, font=name_font, fill=color, anchor="lm")


def finish(img):
    return img.resize((W, H), Image.Resampling.LANCZOS)


# --- 場面


def gesture_demo(gesture, mouse, key, symbol, name, duration):
    frames = []
    for i in range(round(duration * FPS)):
        t = i / FPS
        m, pressed = mouse(t), key(t)
        gesture.step(m, pressed)
        img = wallpaper().copy()
        draw_window(img, gesture.frame)
        paste(img, menu_bar(), 0, 0)
        if gesture.zone:
            zx, zy, zw, zh = gesture.zone
            paste(img, preview_sprite(zw, zh), zx + 4, zy + 4)
        draw_cursor(img, m)
        draw_key(img, (W - 104) / 2, H - KEY_H - 18, 104, symbol, name, pressed)
        frames.append(finish(img))
    return frames


def demo_move():
    # ⌃ を押したまま右下へ運び、離してからカーソルだけ動かす。もう一度押して元の位置へ戻す
    mouse = path(
        (0, 190, 150), (0.8, 190, 150), (2.4, 410, 235, 0.12), (3.2, 455, 285), (3.8, 455, 285),
        (5.4, 235, 200, 0.12), (5.8, 235, 200), (6.4, 190, 150), (6.8, 190, 150),
    )
    key = held((0.6, 2.6), (3.6, 5.6))
    return gesture_demo(Gesture("move", (80, 76, 250, 165)), mouse, key, "⌃", "control", 6.8), 1.7


def demo_resize():
    # ⌥ を押したまま右下へ広げ、もう一度押して元の大きさへ戻す
    mouse = path(
        (0, 230, 140), (0.8, 230, 140), (2.3, 370, 245, -0.1), (2.9, 392, 262), (3.5, 392, 262),
        (5.0, 252, 157, -0.1), (5.4, 252, 157), (5.9, 230, 140), (6.3, 230, 140),
    )
    key = held((0.6, 2.5), (3.3, 5.2))
    return gesture_demo(Gesture("resize", (90, 64, 230, 150)), mouse, key, "⌥", "option", 6.3), 1.9


def demo_snap():
    # 左端で左半分 → 動かすと元の大きさ → 上端で最大化 → 動かして元の位置へ戻す
    mouse = path(
        (0, 290, 110), (0.7, 290, 110), (1.7, 0, 175, 0.08), (2.6, 0, 175), (2.9, 120, 130), (3.2, 120, 130),
        (4.3, 330, 2, -0.08), (5.1, 330, 2), (5.45, 330, 90), (5.8, 330, 90), (7.0, 322, 152),
        (7.4, 322, 152), (7.9, 290, 110), (8.3, 290, 110),
    )
    key = held((0.5, 2.2), (3.05, 4.8), (5.65, 7.2))
    return gesture_demo(Gesture("move", (190, 84, 240, 160)), mouse, key, "⌃", "control", 8.3), 1.95


def demo_input():
    window = (60, 52, 480, 200)
    left, right = held((0.45, 0.62)), held((2.45, 2.62))
    english, kana = "Hello ", "こんにちは"
    english_start, english_step = 1.05, 0.12
    kana_start, kana_step, commit = 3.0, 0.2, 4.3
    # 単押しを判定するのはキーを離したとき
    switches = ((0.62, "A"), (2.62, "あ"))
    duration = 6.4

    text_font = font(FONT_JA, 24)
    bubble_font = font(FONT_JA_BOLD, 17)
    label_font = font(FONT_JA, 12)

    def typed(t, start, step, text):
        return text[: max(0, min(len(text), int((t - start) / step) + 1))] if t >= start else ""

    frames = []
    for i in range(round(duration * FPS)):
        t = i / FPS
        mode, switched_at = "あ", None
        for at, m in switches:
            if t >= at:
                mode, switched_at = m, at
        committed = typed(t, english_start, english_step, english)
        composing = typed(t, kana_start, kana_step, kana)
        if t >= commit:
            committed, composing = committed + composing, ""
        # 最後に何かが起きた時刻から、カーソルの点滅を始める
        events = [english_start + english_step * n for n in range(len(english))]
        events += [kana_start + kana_step * n for n in range(len(kana))] + [commit, *(at for at, _ in switches)]
        last = max([e for e in events if e <= t], default=0)

        img = wallpaper().copy()
        draw_window(img, window, lines=False)
        d = ImageDraw.Draw(img)
        x, y = window[0] + 28, window[1] + TITLE + 58  # 文字のベースライン
        d.text((px(x), px(y)), committed, font=text_font, fill=TEXT, anchor="ls")
        cx = px(x) + text_font.getlength(committed)
        if composing:
            # 変換前の文字には下線を引く
            d.text((cx, px(y)), composing, font=text_font, fill=TEXT, anchor="ls")
            end = cx + text_font.getlength(composing)
            d.line([(cx, px(y + 5)), (end, px(y + 5))], fill=TEXT, width=px(1.5))
            cx = end
        if (t - last) < 0.5 or int((t - last) / 0.5) % 2 == 1:
            d.rectangle([cx + px(1), px(y - 22), cx + px(3) - 1, px(y + 5)], fill=TEXT)
        if switched_at is not None and t - switched_at < 0.9:
            # 切り替えたときに macOS がカーソルの近くに出す入力モードの表示
            alpha = min(1.0, (0.9 - (t - switched_at)) / 0.2)
            bubble = Image.new("RGBA", (px(34), px(30)), (0, 0, 0, 0))
            bd = ImageDraw.Draw(bubble)
            bd.rounded_rectangle(box(0, 0, 34, 30), radius=px(8), fill=TEXT + (round(235 * alpha),))
            bd.text((px(17), px(15)), mode, font=bubble_font, fill=(255, 255, 255, round(255 * alpha)), anchor="mm")
            paste(img, bubble, cx / S - 4, y + 14)
        paste(img, menu_bar(mode), 0, 0)

        # 下に左⌘・スペース・右⌘を並べ、左右の⌘の下に切り替わる先を書く
        key_w, space_w, gap = 112, 150, 10
        kx = (W - key_w * 2 - space_w - gap * 2) / 2
        ky = H - KEY_H - 40
        for kx_, w, symbol, name, pressed, label in (
            (kx, key_w, "⌘", "command", left(t), "英数"),
            (kx + key_w + gap, space_w, None, None, False, None),
            (kx + key_w + space_w + gap * 2, key_w, "⌘", "command", right(t), "かな"),
        ):
            draw_key(img, kx_, ky, w, symbol, name, pressed)
            if label:
                d.text(
                    (px(kx_ + w / 2), px(ky + KEY_H + 16)), label, font=label_font,
                    fill=ACCENT if pressed else MUTED, anchor="mm",
                )
        frames.append(finish(img))
    return frames, 4.8


# --- 書き出し


def build_palette(frames):
    """描くのに使った色はそのまま入れ、残りを縁や影の中間色に割り当てる。
    すべて画像から選ぶと、信号の 3 色やカーソルの黒のように面積の小さい色が落ちる"""
    fixed = [
        WALLPAPER, MENU_BG, MENU_TEXT, MENU_ITEM, WINDOW_BG, TITLE_BG, WINDOW_BORDER, LINE,
        TEXT, MUTED, ACCENT, ACCENT_DARK, KEY_BG, KEY_BORDER, KEY_SHADOW, *TRAFFIC, (0, 0, 0), (255, 255, 255),
    ]
    samples = frames[:: max(1, len(frames) // 16)]
    strip = Image.new("RGB", (W, H * len(samples)))
    for i, frame in enumerate(samples):
        strip.paste(frame, (0, H * i))
    count = COLORS - len(fixed)
    adaptive = strip.quantize(colors=count, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = Image.new("P", (1, 1))
    palette.putpalette(adaptive.getpalette()[: count * 3] + [c for color in fixed for c in color])
    return palette


def save(frames, poster_time, out, name):
    # すべてのフレームで同じパレットを使い、ディザをかけない (動かない部分の色がちらつかず、差分だけが記録されて軽い)
    palette = build_palette(frames)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    indexed[0].save(out / f"{name}.gif", save_all=True, append_images=indexed[1:], duration=1000 // FPS, loop=0)
    indexed[round(poster_time * FPS)].save(out / f"{name}.png", optimize=True)


def main():
    if len(sys.argv) != 2:
        sys.exit(f"使い方: {sys.argv[0]} <出力ディレクトリ>")
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, demo in (("move", demo_move), ("resize", demo_resize), ("snap", demo_snap), ("input", demo_input)):
        frames, poster_time = demo()
        save(frames, poster_time, out, name)
        size = (out / f"{name}.gif").stat().st_size
        print(f"{out / name}.gif: {len(frames)} frames, {size / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
