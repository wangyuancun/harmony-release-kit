#!/usr/bin/env python3
"""把模拟器/真机截图处理成应用市场要求的 9:16 规格（默认 1080×1920）。

为什么需要「补边」而不是直接裁剪
--------------------------------
手机截图常见是 1280×2832（约 9:20），比商店要求的 9:16 更长。
如果直接居中裁到 9:16，会切掉顶部状态栏和底部导航栏；
如果强行拉伸，画面会变形。正确做法是：
  1. 等比缩放到目标高度（1080×1920 时，1280×2832 → 868×1920）；
  2. 左右各补 (1080-868)/2 = 106 px。
补边有两种模式：
  edge  —— 取每行最左/最右 1px 的像素横向拉伸，和页面底色/系统栏自然接缝（推荐）；
  solid —— 用固定颜色填充（适合纯色背景的应用）。

用法
----
  # 单张
  python3 screenshots/make-store-shots.py screenshots/raw/01_home.png -o screenshots/store

  # 整个目录
  python3 screenshots/make-store-shots.py screenshots/raw -o screenshots/store

  # 自定义规格（例如平板 2:3 / 1280×1920）
  python3 screenshots/make-store-shots.py screenshots/raw -o screenshots/store \
      --width 1280 --height 1920 --pad solid --bg "#0B0C10"

输出文件名为「原文件名 + _<宽>x<高>.png」，并打印每张的尺寸与体积。
华为应用市场要求：PNG/JPG，单张 ≤ 5 MB，不允许动图。
"""
import argparse
import os
import sys

from PIL import Image


def parse_color(value):
    value = value.strip().lstrip("#")
    if len(value) == 3:
        value = "".join(c * 2 for c in value)
    if len(value) != 6:
        raise argparse.ArgumentTypeError("颜色格式应为 #RRGGBB")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def pad_edge(img, target_w):
    """用每行最左/最右像素横向拉伸补边，保持上下渐变连续。"""
    w, h = img.size
    pad = (target_w - w) // 2
    if pad <= 0:
        return img
    left = img.crop((0, 0, 1, h)).resize((pad, h), Image.NEAREST)
    right = img.crop((w - 1, 0, w, h)).resize((pad, h), Image.NEAREST)
    canvas = Image.new("RGB", (target_w, h), (0, 0, 0))
    canvas.paste(left, (0, 0))
    canvas.paste(img, (pad, 0))
    canvas.paste(right, (pad + w, 0))
    return canvas


def fit_one(src, dst, target_w, target_h, mode, bg, keep_alpha=False):
    img = Image.open(src)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA" if keep_alpha else "RGB")
    if not keep_alpha:
        img = img.convert("RGB")

    w, h = img.size
    scale = min(target_w / w, target_h / h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    img = img.resize((new_w, new_h), Image.LANCZOS)

    if new_w == target_w and new_h == target_h:
        out = img
    elif new_h == target_h:
        out = pad_edge(img, target_w) if mode == "edge" else _paste_center(img, target_w, target_h, bg)
    else:
        out = _paste_center(img, target_w, target_h, bg)

    out.save(dst, "PNG", optimize=True)
    return out.size, os.path.getsize(dst)


def _paste_center(img, target_w, target_h, bg):
    canvas = Image.new("RGB", (target_w, target_h), bg)
    canvas.paste(img, ((target_w - img.size[0]) // 2, (target_h - img.size[1]) // 2))
    return canvas


def main():
    ap = argparse.ArgumentParser(description="把截图处理成商店规格（默认 1080×1920 / 9:16）")
    ap.add_argument("input", help="输入图片或目录（目录会处理其中所有 png/jpg/jpeg）")
    ap.add_argument("-o", "--output-dir", default="screenshots/store", help="输出目录")
    ap.add_argument("--width", type=int, default=1080)
    ap.add_argument("--height", type=int, default=1920)
    ap.add_argument("--pad", choices=["edge", "solid"], default="edge", help="补边方式")
    ap.add_argument("--bg", type=parse_color, default=(11, 12, 16), help="solid 模式的背景色，如 #0B0C10")
    args = ap.parse_args()

    if args.width * 16 != args.height * 9:
        print(f"提示：{args.width}×{args.height} 不是严格 9:16，继续执行。", file=sys.stderr)

    if os.path.isdir(args.input):
        names = sorted(
            n for n in os.listdir(args.input)
            if n.lower().endswith((".png", ".jpg", ".jpeg"))
        )
        files = [os.path.join(args.input, n) for n in names]
    else:
        files = [args.input]

    if not files:
        print("没有找到图片。", file=sys.stderr)
        return 1

    os.makedirs(args.output_dir, exist_ok=True)
    for src in files:
        stem = os.path.splitext(os.path.basename(src))[0]
        dst = os.path.join(args.output_dir, f"{stem}_{args.width}x{args.height}.png")
        try:
            size, nbytes = fit_one(src, dst, args.width, args.height, args.pad, args.bg)
        except Exception as exc:  # noqa: BLE001
            print(f"失败 {src}: {exc}", file=sys.stderr)
            continue
        flag = "OK" if nbytes <= 5 * 1024 * 1024 else "超过 5MB"
        print(f"{dst}  {size[0]}×{size[1]}  {nbytes / 1024:.0f} KB  [{flag}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
