#!/usr/bin/env python3
"""EisuPlus のアプリアイコン（Icon Composer 形式）を生成する。

キーキャップを対角線で分割し、左上に「A」、右下に「あ」を置いたデザイン。
文字はフォントからアウトラインを取り出して SVG のパスにする（Icon Composer は SVG の <text> を描けないため）。

使い方（fontTools が必要）:
    python3 -m venv /tmp/icon-venv && /tmp/icon-venv/bin/pip install fonttools
    /tmp/icon-venv/bin/python scripts/generate-app-icon.py EisuMod/AppIcon.icon

確認用の PNG は Icon Composer の ictool で書き出せる:
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \\
        EisuMod/AppIcon.icon --export-image --output-file icon.png \\
        --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
"""
import json
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
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


def glyph_path(font, char, center, height):
    glyph_set = font.getGlyphSet()
    name = font.getBestCmap()[ord(char)]
    bounds_pen = BoundsPen(glyph_set)
    glyph_set[name].draw(bounds_pen)
    x0, y0, x1, y1 = bounds_pen.bounds
    s = height / (y1 - y0)
    cx, cy = center
    # フォントは y が上向きなので反転する
    tx = cx - (x0 + x1) / 2 * s
    ty = cy + (y0 + y1) / 2 * s
    pen = SVGPathPen(glyph_set)
    glyph_set[name].draw(pen)
    return f'<path transform="translate({tx:.2f} {ty:.2f}) scale({s:.5f} {-s:.5f})" d="{pen.getCommands()}"/>'


def svg(body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f"{body}</svg>\n"
    )


def rect(d, fill):
    return f'<rect x="{d["x"]}" y="{d["y"]}" width="{d["w"]}" height="{d["h"]}" rx="{d["r"]}" fill="{fill}"/>'


def main(out_dir):
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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <output .icon directory>")
    main(sys.argv[1])
