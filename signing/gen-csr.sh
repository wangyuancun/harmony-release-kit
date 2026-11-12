#!/bin/bash
# 生成 HarmonyOS 发布证书所需的 EC 密钥库与 CSR。
#
# 为什么必须是 EC，不能是 RSA
# ---------------------------
# HarmonyOS 应用签名要求 SHA256withECDSA，AGC 上传 CSR 时会校验公钥算法与曲线。
# 用 RSA 生成的 CSR 在 AGC 会直接提示「上传的CSR文件无效」。
# 正确参数：
#     -keyalg EC -groupname secp384r1 -sigalg SHA256withECDSA
#
# 口令怎么输入
# ------------
# 本脚本不接收口令参数，也不生成口令；keytool 会自己在终端提示输入：
#     Enter keystore password: / Re-enter new password: / Enter key password for <alias>
# 口令只存在于 keytool 进程内存，不落盘、不进 argv、不进 shell history。
# 生成的 p12 请立刻备份到密码管理器或离线介质，丢了无法重新签同一应用。
#
# 用法
# ----
#   bash signing/gen-csr.sh --out-dir ~/keys --alias my_release \
#     --dname "CN=Your Name, OU=Dev, O=Your Org, L=City, ST=Province, C=CN"
#
# 可选参数
#   --validity <天数>     默认 9125（25 年；AGC 实际签发证书有效期以平台为准）
#   --keyalg <算法>       默认 EC
#   --groupname <曲线>    默认 secp384r1
#   --sigalg <签名算法>   默认 SHA256withECDSA
#
# 产出
#   <out-dir>/<alias>.p12   密钥库（务必备份，不要提交到 git）
#   <out-dir>/<alias>.csr   上传到 AGC 创建发布证书
#
# 生成后请先自查（脚本会自动执行一遍）：
#   openssl req -in <alias>.csr -noout -text | grep -E "Public Key Algorithm|ASN1 OID|Signature Algorithm"
# 期望看到 id-ecPublicKey / secp384r1 / ecdsa-with-SHA256。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR=""
ALIAS=""
DNAME=""
VALIDITY=9125
KEYALG="EC"
GROUPNAME="secp384r1"
SIGALG="SHA256withECDSA"

while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --alias) ALIAS="${2:-}"; shift 2 ;;
    --dname) DNAME="${2:-}"; shift 2 ;;
    --validity) VALIDITY="${2:-}"; shift 2 ;;
    --keyalg) KEYALG="${2:-}"; shift 2 ;;
    --groupname) GROUPNAME="${2:-}"; shift 2 ;;
    --sigalg) SIGALG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -n "$OUT_DIR" ] && [ -n "$ALIAS" ] && [ -n "$DNAME" ] || {
  echo "缺少必填参数：--out-dir / --alias / --dname" >&2
  exit 2
}

mkdir -p "$OUT_DIR"
P12="$OUT_DIR/$ALIAS.p12"
CSR="$OUT_DIR/$ALIAS.csr"

[ -e "$P12" ] && { echo "已存在密钥库，拒绝覆盖: $P12" >&2; exit 1; }
[ -e "$CSR" ] && { echo "已存在 CSR，拒绝覆盖: $CSR" >&2; exit 1; }

echo "==> 生成密钥库（按提示输入两次以上口令）"
keytool -genkeypair \
  -alias "$ALIAS" \
  -keyalg "$KEYALG" \
  -groupname "$GROUPNAME" \
  -sigalg "$SIGALG" \
  -dname "$DNAME" \
  -validity "$VALIDITY" \
  -keystore "$P12" \
  -storetype PKCS12

echo "==> 生成 CSR"
keytool -certreq \
  -alias "$ALIAS" \
  -keystore "$P12" \
  -file "$CSR" \
  -sigalg "$SIGALG"

if [ -e "$CSR" ]; then
  echo "==> 自查 CSR 参数"
  openssl req -in "$CSR" -noout -text \
    | grep -E "Public Key Algorithm|ASN1 OID|Signature Algorithm" || true
fi

echo "==> 完成"
ls -l "$P12" "$CSR"
echo "下一步：把 $CSR 上传到 AGC「证书」页创建发布证书，再把签发的 .cer 与 Profile .p7b 下载回来。"
