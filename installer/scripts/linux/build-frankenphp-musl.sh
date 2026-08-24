#!/usr/bin/env bash
#
# 在 Alpine 容器内以 musl 完全静态方式定制构建 FrankenPHP。
#
# musl 完全静态产物不链接 glibc，可运行于任意 glibc 版本（Ubuntu/Debian/RHEL
# 甚至 Alpine 本身），从根本上避免 "GLIBC_x.yy not found"。这也是 FrankenPHP
# 官方静态构建的默认方式。
#
# spc（static-php-cli）运行需要 PHP >= 8.4，Alpine 3.21 通过 apk 提供 php84。
#
# 环境变量:
#   FRAMPP_BUILD_IMAGE 构建镜像（默认 alpine:3.21）
#
# 用法: build-frankenphp-musl.sh <frankenphp-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
FP_VERSION="${3:-unknown}"
IMAGE="${FRAMPP_BUILD_IMAGE:-alpine:3.21}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 FrankenPHP 源码包: $SRC_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
SRC_TAR_ABS="$(abs "$SRC_TAR")"
OUT_DIR_ABS="$(abs "$OUT_DIR")"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "==> Docker 不可用，回退宿主裸构建（musl 静态，需宿主机支持）" >&2
    exec bash "$HERE/build-frankenphp.sh" "$SRC_TAR" "$OUT_DIR" "$FP_VERSION"
fi

echo "==> 使用 Docker ($IMAGE) musl 完全静态构建 FrankenPHP $FP_VERSION ..."
docker run --rm \
    -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
    -e "FRAMPP_PHP_VERSION=${FRAMPP_PHP_VERSION:-8.5.9}" \
    -e "FRAMPP_SPC_LIBC=musl" \
    -e "FP_VERSION=$FP_VERSION" \
    -v "$SRC_TAR_ABS:/src/frankenphp.tar.gz:ro" \
    -v "$OUT_DIR_ABS:/out" \
    -v "$HERE/build-frankenphp.sh:/build-frankenphp.sh:ro" \
    "$IMAGE" sh -c '
set -eu
apk add --no-cache \
    bash git curl jq xz unzip ca-certificates \
    build-base cmake bison re2c pkgconf autoconf automake libtool \
    php84 php84-curl php84-mbstring php84-xml php84-sodium \
    php84-dom php84-openssl php84-posix php84-pcntl php84-phar php84-iconv \
    php84-tokenizer php84-ctype php84-simplexml php84-xmlwriter php84-xmlreader \
    >/dev/null
# Alpine 的 PHP 8.4 可执行文件名为 php84，composer 需要 `php` 命令
ln -sf /usr/bin/php84 /usr/local/bin/php
# Composer 2（用 Alpine 的 PHP 8.4 安装）
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
rm -f /tmp/composer-setup.php
bash /build-frankenphp.sh /src/frankenphp.tar.gz /out "$FP_VERSION"
chown -R "$HOST_UID:$HOST_GID" /out
'

echo "==> 校验产物为静态二进制（无 GLIBC 依赖）..."
if file "$OUT_DIR/frankenphp" | grep -qi "statically linked"; then
    echo "FRANKENPHP_STATIC_OK version=$FP_VERSION"
else
    echo "警告: 产物未报告为静态链接，请确认无 glibc 依赖" >&2
fi
echo "FRANKENPHP_MUSL_BUILD_OK version=$FP_VERSION image=$IMAGE"
