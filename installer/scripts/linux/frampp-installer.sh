#!/usr/bin/env sh
#
# FRAMPP 一键安装包（__PLATFORM__）/ FRAMPP One-Click Installer (__PLATFORM__)
#
# 单文件自解压安装器：本文件头部为安装脚本，尾部追加压缩载荷（tar.gz）。
# 运行后自动校验完整性、解压到目标目录并执行 bin/frampp init（初始化 + 启动）。
# Single-file self-extracting installer: this header is the launcher script,
# the tar.gz payload is appended at the end. It verifies integrity, extracts
# into the target directory and runs bin/frampp init (init + start).
#
# 用法 / Usage:
#   ./frampp-__APP_VERSION__-__ENV__.run [--prefix <dir>] [--extract-only] [--skip-start] [--help]
#

set -e

PAYLOAD_OFFSET="0000000000000000"
PAYLOAD_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
APP_VERSION="__APP_VERSION__"
CHANNEL="__CHANNEL__"
PLATFORM="__PLATFORM__"
ENV_NAME="__ENV__"

DEFAULT_PREFIX="${HOME:-.}/frampp"
PREFIX=""
EXTRACT_ONLY=0
SKIP_START=0

usage() {
    cat <<EOF
FRAMPP $APP_VERSION One-Click Installer / 一键安装包 (channel: $CHANNEL)

Usage / 用法:
  ./$(basename "$0") [options/选项]

Options / 选项:
   --prefix <dir>    installation directory / 安装目录 (default / 默认: $DEFAULT_PREFIX)
   --extract-only    extract payload only, skip init / 仅解压载荷，不执行初始化
   --skip-start      initialize but do not start services / 安装时不启动服务
   --version         show version / 显示版本
   --help, -h        show this help / 显示帮助

Examples / 示例:
  ./$(basename "$0")
  ./$(basename "$0") --prefix ~/apps/frampp
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            if [ $# -lt 2 ]; then
                echo "ERROR: --prefix requires an argument / --prefix 需要参数" >&2
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
            echo "FRAMPP $APP_VERSION ($CHANNEL) - $PLATFORM"
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown option / 未知选项: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[ -n "$PREFIX" ] || PREFIX="$DEFAULT_PREFIX"

# 基础工具检查 / basic tool check
for tool in tail tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: missing tool / 缺少工具: $tool" >&2
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
        echo "WARN: sha256sum/openssl not found; skipping integrity check / 未找到 sha256sum/openssl，跳过完整性校验" >&2
        return 0
    fi
    if [ "$actual" != "$PAYLOAD_SHA256" ]; then
        echo "ERROR: installer integrity check failed / 安装包校验失败" >&2
        exit 1
    fi
}

echo "==> FRAMPP $APP_VERSION one-click install / 一键安装 ($PLATFORM)"
echo "==> target directory / 目标目录: $PREFIX"

verify_payload

# 解压载荷到目标目录（幂等：已初始化则 init 自动跳过）
# Extract payload into the target directory (idempotent)
mkdir -p "$PREFIX"
tail -c +"$PAYLOAD_OFFSET" "$0" | tar -xzf - -C "$PREFIX"

cd "$PREFIX"
if [ "$EXTRACT_ONLY" -eq 1 ]; then
    echo "==> payload extracted to / 载荷已解压到: $PREFIX"
    echo "==> init skipped / 已跳过初始化 (--extract-only)."
elif [ -x "./bin/frampp" ]; then
    ./bin/frampp init
    if [ "$SKIP_START" -eq 1 ]; then
        echo "==> service start skipped / 已跳过服务启动 (--skip-start)."
    else
        ./bin/frampp start all || true
        ./bin/frampp status || true
    fi
else
    echo "ERROR: extraction incomplete / 解压不完整: bin/frampp not found" >&2
    exit 1
fi
# 显式退出，避免 shell 继续读取尾部二进制载荷（makeself 惯例）
# Explicit exit so the shell does not read the binary payload that follows
exit 0
