#!/usr/bin/env python3
"""EisuPlus のアプリアイコン（Icon Composer 形式）とメニューバーアイコンを生成する。

キーキャップを対角線で分割し、左上に「A」、右下に「あ」を置いたデザイン。
文字はフォントからアウトラインを取り出して SVG のパスにする（Icon Composer は SVG の <text> を描けないため）。
メニューバーアイコンは同じデザインを単色のテンプレート画像にしたもので、右下の塗りから「あ」を抜く。

使い方（fontTools が必要）:
    python3 -m venv /tmp/icon-venv && /tmp/icon-venv/bin/pip install fonttools
    /tmp/icon-venv/bin/python scripts/generate-app-icon.py EisuMod/AppIcon.icon EisuMod/Assets.xcassets

確認用の PNG は Icon Composer の ictool で書き出せる:
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \\
        EisuMod/AppIcon.icon --export-image --output-file icon.png \\
        --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
"""
import json
import shutil
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# 1024pt のキャンバス上の座標
BASE = dict(x=184, y=196, w=656, h=652, r=136)  # キーキャップの側面
TOP = dict(x=226, y=218, w=572, h=500, r=96)  # キートップ
A_CENTER, A_HEIGHT = (372, 408), 176
KANA_CENTER, KANA_HEIGHT = (652, 566), 188

COLOR_BG = "extended-srgb:0.11765,0.16471,0.23137,1.00000"  # #1E2A3B
COLOR_BASE = "#8E9BB0"
COLOR_TOP = "#F4F6FA"
COLOR_KANA_HALF = "#2F6BFF"
COLOR_A = "#1E2A3B"
COLOR_KANA = "#FFFFFF"

# メニューバーアイコン（pt 単位）。キーキャップは正方形にして、対角線が角丸の中心を通るようにする
MENU_SIZE = 18
MENU_CAP = dict(x=0.5, y=0.5, s=17, r=4.2)
MENU_RING = 1.4  # キーキャップの縁の太さ
MENU_A_CENTER, MENU_A_HEIGHT = (6.2, 6.4), 5.8
MENU_KANA_CENTER, MENU_KANA_HEIGHT = (11.9, 11.7), 7.0
MENU_PAUSED_OPACITY = 0.35


def glyph_transform(font, char, center, height):
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[font.getBestCmap()[ord(char)]]
    bounds_pen = BoundsPen(glyph_set)
    glyph.draw(bounds_pen)
    x0, y0, x1, y1 = bounds_pen.bounds
    s = height / (y1 - y0)
    cx, cy = center
    # フォントは y が上向きなので反転する
    tx = cx - (x0 + x1) / 2 * s
    ty = cy + (y0 + y1) / 2 * s
    return glyph_set, glyph, (tx, ty, s)


def glyph_path(font, char, center, height):
    glyph_set, glyph, (tx, ty, s) = glyph_transform(font, char, center, height)
    pen = SVGPathPen(glyph_set)
    glyph.draw(pen)
    return f'<path transform="translate({tx:.2f} {ty:.2f}) scale({s:.5f} {-s:.5f})" d="{pen.getCommands()}"/>'


def glyph_d(font, char, center, height):
    """座標変換済みのアウトライン。他の図形と 1 つのパスにまとめるときに使う。"""
    glyph_set, glyph, (tx, ty, s) = glyph_transform(font, char, center, height)
    pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.3f}".rstrip("0").rstrip("."))
    glyph.draw(TransformPen(pen, (s, 0, 0, -s, tx, ty)))
    return pen.getCommands()


def svg(body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f"{body}</svg>\n"
    )


def rect(d, fill):
    return f'<rect x="{d["x"]}" y="{d["y"]}" width="{d["w"]}" height="{d["h"]}" rx="{d["r"]}" fill="{fill}"/>'


def rounded_square(x, y, s, r):
    x1, y1 = x + s, y + s
    return (
        f"M{x + r} {y}H{x1 - r}A{r} {r} 0 0 1 {x1} {y + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
        f"H{x + r}A{r} {r} 0 0 1 {x} {y1 - r}V{y + r}A{r} {r} 0 0 1 {x + r} {y}Z"
    )


def lower_right_half(x, y, s, r):
    """角丸の正方形のうち、右上と左下の角を結ぶ対角線より右下の部分。"""
    x1, y1 = x + s, y + s
    d = r * (1 - 2**-0.5)  # 対角線は角丸の中心を通り、弧の中点で輪郭と交わる
    return (
        f"M{x1 - d:.3f} {y + d:.3f}A{r} {r} 0 0 1 {x1} {y + r}V{y1 - r}A{r} {r} 0 0 1 {x1 - r} {y1}"
        f"H{x + r}A{r} {r} 0 0 1 {x + d:.3f} {y1 - d:.3f}Z"
    )


def menu_bar_svg(font, opacity=None):
    c, ring = MENU_CAP, MENU_RING
    inner = dict(x=c["x"] + ring, y=c["y"] + ring, s=c["s"] - ring * 2, r=c["r"] - ring)
    # 縁は外側と内側の角丸を、「あ」は右下の塗りを evenodd で抜いて描く（テンプレート画像は透明度だけが使われる）。
    # mask で抜くと低い解像度でラスタライズされて文字がにじむ
    body = (
        f'<path fill-rule="evenodd" d="{rounded_square(**c)}{rounded_square(**inner)}"/>'
        f'<path fill-rule="evenodd" d="{lower_right_half(**c)}{glyph_d(font, "あ", MENU_KANA_CENTER, MENU_KANA_HEIGHT)}"/>'
        f'<path d="{glyph_d(font, "A", MENU_A_CENTER, MENU_A_HEIGHT)}"/>'
    )
    if opacity is not None:
        body = f'<g opacity="{opacity}">{body}</g>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{MENU_SIZE}" height="{MENU_SIZE}" '
        f'viewBox="0 0 {MENU_SIZE} {MENU_SIZE}">{body}</svg>\n'
    )


def write_menu_bar_icons(font, xcassets_dir):
    variants = {
        "MenuBarIcon": menu_bar_svg(font),
        # 一時停止中は薄く描いて、無効になっていることを示す
        "MenuBarIconPaused": menu_bar_svg(font, opacity=MENU_PAUSED_OPACITY),
    }
    # バリアントを改名・削除したときに古い imageset が残らないようにする
    for stale in Path(xcassets_dir).glob("MenuBarIcon*.imageset"):
        shutil.rmtree(stale)
    for name, content in variants.items():
        imageset = Path(xcassets_dir) / f"{name}.imageset"
        imageset.mkdir(parents=True, exist_ok=True)
        (imageset / f"{name}.svg").write_text(content)
        contents = {
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {
                "preserves-vector-representation": True,
                "template-rendering-intent": "template",
            },
        }
        # Xcode と同じ書式にして、Xcode で開いたときに差分が出ないようにする
        (imageset / "Contents.json").write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")


def main(out_dir, xcassets_dir):
    out = Path(out_dir)
    assets = out / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    font = TTFont(FONT, fontNumber=0)

    x0, y0, x1, y1 = TOP["x"], TOP["y"], TOP["x"] + TOP["w"], TOP["y"] + TOP["h"]
    kana_half = (
        '<defs><clipPath id="top">'
        f'<rect x="{x0}" y="{y0}" width="{TOP["w"]}" height="{TOP["h"]}" rx="{TOP["r"]}"/>'
        "</clipPath></defs>"
        f'<polygon clip-path="url(#top)" points="{x1},{y0} {x1},{y1} {x0},{y1}" fill="{COLOR_KANA_HALF}"/>'
    )

    layers = {
        "base.svg": svg(rect(BASE, COLOR_BASE)),
        "top.svg": svg(rect(TOP, COLOR_TOP)),
        "kana-half.svg": svg(kana_half),
        "eisu.svg": svg(f'<g fill="{COLOR_A}">{glyph_path(font, "A", A_CENTER, A_HEIGHT)}</g>'),
        "kana.svg": svg(f'<g fill="{COLOR_KANA}">{glyph_path(font, "あ", KANA_CENTER, KANA_HEIGHT)}</g>'),
    }
    # レイヤーを改名・削除したときに古い SVG が残らないようにする
    for stale in assets.glob("*.svg"):
        stale.unlink()
    for name, content in layers.items():
        (assets / name).write_text(content)

    def layer(name, glass):
        return {
            "glass": glass,
            "image-name": f"{name}.svg",
            "name": name,
        }

    icon = {
        "fill": {"automatic-gradient": COLOR_BG},
        "groups": [
            # 先頭のグループ・レイヤーほど手前に描かれる
            {
                "layers": [layer("kana", False), layer("eisu", False)],
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": False, "value": 0.5},
            },
            # キーキャップだけガラスにして縁にハイライトを出す。文字までガラスにすると輪郭がにじむ
            {
                "layers": [layer("kana-half", True), layer("top", True), layer("base", True)],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
            },
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (out / "icon.json").write_text(json.dumps(icon, indent=2, ensure_ascii=False) + "\n")

    write_menu_bar_icons(font, xcassets_dir)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <output .icon directory> <output .xcassets directory>")
    main(sys.argv[1], sys.argv[2])
