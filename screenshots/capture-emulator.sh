#!/bin/bash
# 从模拟器/真机批量抓截图到本地目录。
#
# 用法：
#   bash screenshots/capture-emulator.sh -o screenshots/raw -p 01_home
#   bash screenshots/capture-emulator.sh -s 127.0.0.1:5555 -o screenshots/raw -p 02_stats
#
# 参数：
#   -s <serial>   hdc 设备序列号，默认取 `hdc list targets` 的第一行
#   -o <dir>      本地输出目录，默认 screenshots/raw
#   -p <prefix>   文件名前缀，默认 shot（会加时间戳，避免覆盖）
#   -r <remote>   设备端临时路径，默认 /data/local/tmp/_shot.jpeg
#
# 说明：截图前请先在设备上把页面切到要拍的状态，再执行本脚本。
#      系统状态栏时间会随截图时刻变化，建议同一批截图连续拍完再补边。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVECO="${DEVECO_HOME:-$HOME/Applications/DevEco-Studio-26.0.0.app/Contents}"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
SERIAL=""
OUT_DIR="$ROOT/screenshots/raw"
PREFIX="shot"
REMOTE="/data/local/tmp/_shot.jpeg"

while getopts "s:o:p:r:h" opt; do
  case "$opt" in
    s) SERIAL="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    p) PREFIX="$OPTARG" ;;
    r) REMOTE="$OPTARG" ;;
    h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) exit 2 ;;
  esac
done

[ -x "$HDC" ] || { echo "找不到 hdc: $HDC（可用 DEVECO_HOME 指定 IDE 的 Contents 路径）" >&2; exit 1; }

if [ -z "$SERIAL" ]; then
  SERIAL="$("$HDC" list targets 2>/dev/null | head -1 | tr -d '\r')"
fi
[ -n "$SERIAL" ] && [ "$SERIAL" != "[Empty]" ] || {
  echo "没有可用设备，请先启动模拟器/连接真机。" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOCAL="$OUT_DIR/${PREFIX}_${STAMP}.jpeg"

"$HDC" -t "$SERIAL" shell snapshot_display -f "$REMOTE"
"$HDC" -t "$SERIAL" file recv "$REMOTE" "$LOCAL"
"$HDC" -t "$SERIAL" shell rm -f "$REMOTE" >/dev/null 2>&1 || true

echo "已保存: $LOCAL"
sips -g pixelWidth -g pixelHeight "$LOCAL" 2>/dev/null | tail -2 || true
echo "下一步: python3 screenshots/make-store-shots.py \"$LOCAL\" -o screenshots/store"
