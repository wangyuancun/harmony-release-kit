#!/bin/bash
# 通用 release 签名脚本：给 HAP 和 APP 签名并校验产物。
#
# 为什么用脚本而不是 build-profile.json5 的 signingConfigs
# ------------------------------------------------------------
# 1) hvigor 的 signingConfigs.storePassword / keyPassword 只接受 DevEco Studio
#    用「p12 同目录下 material/」密钥材料加密出来的密文；没有 material/ 时
#    直接报 SIGNING_FAILED_* / KEY_PASSWORD_VALID_FAILED。
# 2) 即使填了密文，hvigor 解密后仍会把明文口令作为 -keystorePwd / -keyPwd
#    传给 java 子进程（ps 可见），不满足「口令不进命令行」的要求。
# 因此命令行签名统一走本脚本：口令在终端交互输入，经 pty 传给 hap-sign-tool，
# 不写文件、不进 argv、不进环境变量。
#
# 口令是怎么安全传进去的（重要原理）
# ----------------------------------
# hap-sign-tool 在 -pwdInputMode 1 下依次提示：
#     please input KeystorePwd (timeout 30 seconds):
#     please input KeyPwd      (timeout 30 seconds):
# 它内部用 JDK Console.readPassword() 读取，而 readPassword 会丢弃「在它开始读
# 之前就已经进入终端输入缓冲」的字符（type-ahead）。所以不能提前把口令管道灌进去，
# 否则会报 "keystore password was incorrect"（详见同目录 ptysign.py 的注释）。
# 本脚本用 ptysign.py 起一个 pty：等提示真正打印出来后再写口令，回显此时已关闭。
#
# 用法
# ----
#   bash signing/sign-release.sh \
#     --p12 ~/keys/my_release.p12 \
#     --cer signing/my_release.cer \
#     --p7b signing/my_release_profileRelease.p7b \
#     --alias my_alias
#
# 常用可选参数
#   --root <工程根>            默认取脚本所在目录的上一级
#   --deveco <Contents 路径>   默认 $DEVECO_HOME，或 ~/Applications/DevEco-Studio-26.0.0.app/Contents
#   --sign-alg <算法>          默认 SHA256withECDSA（HarmonyOS 发布证书要求 EC）
#   --compat-version <API>     默认从 SDK 的 sdk-pkg.json 读 apiVersion
#   --hap <未签名 hap>         默认 entry/build/default/outputs/default/entry-default-unsigned.hap
#   --app <未签名 app>         默认自动在 build/outputs/default/ 下找 *-unsigned.app
#   --out-dir <输出目录>       默认与输入文件同目录
#   --no-verify                跳过签名后的 verify-app
#
# 前置条件：已经 assembleHap 且 Build App(s) 产出未签名 .app；
#           p12 / cer / p7b 三件套已从 AGC 下载齐全。
#
# 注意：本脚本不生成密钥库，也不下载证书。生成密钥库与 CSR 见 signing/gen-csr.sh。

set -euo pipefail

usage() {
  sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
P12=""
CER=""
P7B=""
ALIAS=""
SIGN_ALG="SHA256withECDSA"
COMPAT_VERSION=""
HAP_IN=""
APP_IN=""
OUT_DIR=""
DO_VERIFY=1
DEVECO="${DEVECO_HOME:-$HOME/Applications/DevEco-Studio-26.0.0.app/Contents}"

while [ $# -gt 0 ]; do
  case "$1" in
    --p12) P12="${2:-}"; shift 2 ;;
    --cer) CER="${2:-}"; shift 2 ;;
    --p7b) P7B="${2:-}"; shift 2 ;;
    --alias) ALIAS="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --deveco) DEVECO="${2:-}"; shift 2 ;;
    --sign-alg) SIGN_ALG="${2:-}"; shift 2 ;;
    --compat-version) COMPAT_VERSION="${2:-}"; shift 2 ;;
    --hap) HAP_IN="${2:-}"; shift 2 ;;
    --app) APP_IN="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --no-verify) DO_VERIFY=0; shift ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
done

[ -n "$P12" ] && [ -n "$CER" ] && [ -n "$P7B" ] && [ -n "$ALIAS" ] || {
  echo "缺少必填参数：--p12 / --cer / --p7b / --alias" >&2
  usage
}

JAVA="$DEVECO/jbr/Contents/Home/bin/java"
TOOL="$DEVECO/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
DRIVER="$SCRIPT_DIR/ptysign.py"

# 未指定时从 SDK 元数据推 API 版本（例如 26）
if [ -z "$COMPAT_VERSION" ]; then
  SDK_PKG="$DEVECO/sdk/default/sdk-pkg.json"
  if [ -f "$SDK_PKG" ]; then
    COMPAT_VERSION="$(sed -n 's/.*"apiVersion"[[:space:]]*:[[:space:]]*"\([0-9]*\)".*/\1/p' "$SDK_PKG" | head -1)"
  fi
  COMPAT_VERSION="${COMPAT_VERSION:-26}"
fi

# 默认产物路径
if [ -z "$HAP_IN" ]; then
  HAP_IN="$ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
fi
if [ -z "$APP_IN" ]; then
  APP_IN="$(find "$ROOT/build/outputs/default" -maxdepth 1 -name "*-unsigned.app" 2>/dev/null | head -1 || true)"
fi

HAP_DIR="${OUT_DIR:-$(dirname "$HAP_IN")}"
APP_DIR="${OUT_DIR:-$(dirname "${APP_IN:-$HAP_IN}")}"
HAP_OUT="$HAP_DIR/$(basename "${HAP_IN%-unsigned.hap}")-signed.hap"
APP_OUT="$APP_DIR/$(basename "${APP_IN:-app-unsigned.app}" | sed 's/-unsigned\.app$//')-signed.app"
VERIFY_DIR="$SCRIPT_DIR/verify"

for f in "$JAVA" "$TOOL" "$DRIVER" "$P12" "$CER" "$P7B" "$HAP_IN"; do
  [ -e "$f" ] || { echo "缺少文件: $f" >&2; exit 1; }
done
if [ -n "$APP_IN" ]; then
  [ -e "$APP_IN" ] || { echo "缺少文件: $APP_IN" >&2; exit 1; }
fi

mkdir -p "$HAP_DIR" "$APP_DIR" "$VERIFY_DIR"

sign_one() {
  local in_file="$1"
  local out_file="$2"
  shift 2
  rm -f "$out_file"
  python3 "$DRIVER" "KeystorePwd" "KeyPwd" -- \
    "$JAVA" -jar "$TOOL" sign-app \
      -mode localSign \
      -keyAlias "$ALIAS" \
      -appCertFile "$CER" \
      -profileFile "$P7B" \
      -signAlg "$SIGN_ALG" \
      -keystoreFile "$P12" \
      -inFile "$in_file" \
      -outFile "$out_file" \
      -pwdInputMode 1 \
      "$@"
}

echo "==> 签 HAP: $HAP_IN"
if ! sign_one "$HAP_IN" "$HAP_OUT" -compatibleVersion "$COMPAT_VERSION"; then
  echo "HAP 签名失败（完整输出见上）。" >&2
  exit 2
fi
[ -s "$HAP_OUT" ] || { echo "HAP 未生成: $HAP_OUT" >&2; exit 2; }

if [ -n "$APP_IN" ]; then
  echo "==> 签 APP: $APP_IN"
  if ! sign_one "$APP_IN" "$APP_OUT"; then
    echo "APP 签名失败（完整输出见上）。" >&2
    exit 3
  fi
  [ -s "$APP_OUT" ] || { echo "APP 未生成: $APP_OUT" >&2; exit 3; }
else
  echo "==> 未找到未签名 .app，跳过 APP 签名（上架需要 .app，请先 Build App(s)）" >&2
fi

if [ "$DO_VERIFY" = "1" ]; then
  echo "==> 校验"
  "$JAVA" -jar "$TOOL" verify-app -inFile "$HAP_OUT" \
    -outCertChain "$VERIFY_DIR/hap_chain.cer" -outProfile "$VERIFY_DIR/hap_profile.p7b" 2>&1 | tail -6
  if [ -n "$APP_IN" ]; then
    "$JAVA" -jar "$TOOL" verify-app -inFile "$APP_OUT" \
      -outCertChain "$VERIFY_DIR/app_chain.cer" -outProfile "$VERIFY_DIR/app_profile.p7b" 2>&1 | tail -6
  fi
fi

echo "==> 产物"
ls -l "$HAP_OUT"
[ -n "$APP_IN" ] && ls -l "$APP_OUT"
shasum -a 256 "$HAP_OUT" 2>/dev/null || true
[ -n "$APP_IN" ] && shasum -a 256 "$APP_OUT" 2>/dev/null || true
