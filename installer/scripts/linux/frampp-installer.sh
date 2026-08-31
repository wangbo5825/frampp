#!/usr/bin/env sh
#
# FRAMPP 一键安装包（Linux x86_64）/ FRAMPP One-Click Installer (Linux x86_64)
#
# 单文件自解压安装器：本文件头部为安装脚本，尾部追加压缩载荷（tar.gz）。
# 运行后自动校验完整性、解压到目标目录并执行 bin/frampp init（初始化 + 启动）。
# Single-file self-extracting installer: this header is the launcher script,
# the tar.gz payload is appended at the end. It verifies integrity, extracts
# into the target directory and runs bin/frampp init (init + start).
#
# 用法 / Usage:
#   ./frampp-__APP_VERSION__-linux-x86_64.run [--prefix <dir>] [--extract-only] [--skip-start] [--help]
#

set -e

PAYLOAD_OFFSET="0000000000000000"
PAYLOAD_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
APP_VERSION="__APP_VERSION__"
CHANNEL="__CHANNEL__"

DEFAULT_PREFIX="${HOME:-.}/frampp"
PREFIX=""
EXTRACT_ONLY=0
SKIP_START=0

usage() {
    cat <<EOF
FRAMPP $APP_VERSION 一键安装包 / One-Click Installer (channel: $CHANNEL)

用法 / Usage:
  ./$(basename "$0") [选项/options]

选项 / Options:
   --prefix <dir>    安装目录 / installation directory（默认 / default: $DEFAULT_PREFIX）
   --extract-only    仅解压载荷，不执行初始化 / extract payload only, skip init
   --skip-start      安装时不启动服务 / initialize but do not start services
   --version         显示版本 / show version
   --help, -h        显示帮助 / show this help

示例 / Examples:
  ./$(basename "$0")
  ./$(basename "$0") --prefix ~/apps/frampp
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            if [ $# -lt 2 ]; then
                echo "ERROR: --prefix 需要参数 / requires an argument" >&2
                exit 2
            fi
            PREFIX="$2"
            shift 2
            ;;
        --extract-only)
            EXTRACT_ONLY=1
            shift
            ;;
        --skip-start)
            SKIP_START=1
            shift
            ;;
        --version)
            echo "FRAMPP $APP_VERSION ($CHANNEL) - Linux x86_64"
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: 未知选项 / unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[ -n "$PREFIX" ] || PREFIX="$DEFAULT_PREFIX"

# 基础工具检查 / basic tool check
for tool in tail tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: 缺少工具 / missing tool: $tool" >&2
        exit 1
    fi
done

# 完整性校验（sha256sum 或 openssl） / integrity verification
verify_payload() {
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(tail -c +"$PAYLOAD_OFFSET" "$0" | sha256sum | cut -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(tail -c +"$PAYLOAD_OFFSET" "$0" | openssl dgst -sha256 | awk '{print $NF}')
    else
        echo "WARN: 未找到 sha256sum/openssl，跳过完整性校验 / integrity check skipped" >&2
        return 0
    fi
    if [ "$actual" != "$PAYLOAD_SHA256" ]; then
        echo "ERROR: 安装包校验失败 / installer integrity check failed" >&2
        exit 1
    fi
}

echo "==> FRAMPP $APP_VERSION 一键安装 / one-click install (Linux x86_64)"
echo "==> 目标目录 / target directory: $PREFIX"

verify_payload

# 解压载荷到目标目录（幂等：已初始化则 init 自动跳过）
# Extract payload into the target directory (idempotent)
mkdir -p "$PREFIX"
tail -c +"$PAYLOAD_OFFSET" "$0" | tar -xzf - -C "$PREFIX"

cd "$PREFIX"
if [ "$EXTRACT_ONLY" -eq 1 ]; then
    echo "==> 载荷已解压到 / payload extracted to: $PREFIX"
    echo "==> 已跳过初始化 / init skipped (--extract-only)."
elif [ -x "./bin/frampp" ]; then
    ./bin/frampp init
    if [ "$SKIP_START" -eq 1 ]; then
        echo "==> 已跳过服务启动 / service start skipped (--skip-start)."
    else
        ./bin/frampp start all || true
        ./bin/frampp status || true
    fi
else
    echo "ERROR: 解压不完整 / extraction incomplete: bin/frampp not found" >&2
    exit 1
fi
# 显式退出，避免 shell 继续读取尾部二进制载荷（makeself 惯例）
# Explicit exit so the shell does not read the binary payload that follows
exit 0
