#!/usr/bin/env bash
#
# 在固定旧 glibc 基线容器内定制构建 FrankenPHP。
#
# 同 build-mariadb-glibc.sh 的原因：glibc 向下兼容，故在旧 glibc 容器内编译，
# 使产物能在更多旧发行版上运行。默认 ubuntu:20.04（glibc 2.31）。
#
# 环境变量:
#   FRAMPP_GLIBC_IMAGE  构建镜像（默认 ubuntu:20.04）
#   FRAMPP_GLIBC_MAX    允许的最高 GLIBC 符号版本（默认 2.31）
#
# 用法: build-frankenphp-glibc.sh <frankenphp-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
FP_VERSION="${3:-unknown}"
IMAGE="${FRAMPP_GLIBC_IMAGE:-ubuntu:20.04}"
GLIBC_MAX="${FRAMPP_GLIBC_MAX:-2.31}"
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
    echo "==> Docker 不可用，回退宿主裸构建（注意：glibc 基线可能过高）" >&2
    exec bash "$HERE/build-frankenphp.sh" "$SRC_TAR" "$OUT_DIR" "$FP_VERSION"
fi

echo "==> 使用 Docker ($IMAGE) 固定 glibc 基线构建 FrankenPHP $FP_VERSION ..."
docker run --rm \
    -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
    -e "FRAMPP_PHP_VERSION=${FRAMPP_PHP_VERSION:-8.5.9}" \
    -e "FRAMPP_SPC_LIBC=${FRAMPP_SPC_LIBC:-glibc}" \
    -v "$SRC_TAR_ABS:/src/frankenphp.tar.gz:ro" \
    -v "$OUT_DIR_ABS:/out" \
    -v "$HERE/build-frankenphp.sh:/build-frankenphp.sh:ro" \
    "$IMAGE" bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y --no-install-recommends \
    build-essential cmake bison re2c pkg-config autoconf \
    libssl-dev libpcre2-dev zlib1g-dev libncurses-dev libcurl4-openssl-dev \
    libxml2-dev libonig-dev libreadline-dev libargon2-dev libsodium-dev \
    libsqlite3-dev libbz2-dev libzip-dev libyaml-dev libffi-dev \
    libicu-dev liblzma-dev libxslt1-dev libjpeg-dev libpng-dev libwebp-dev \
    libfreetype6-dev libgmp-dev libedit-dev libaio-dev \
    libgnutls28-dev liblz4-dev libsnappy-dev libpam0g-dev libkrb5-dev \
    libsystemd-dev libcrack2-dev libcap-dev \
    php-cli unzip git curl jq xz-utils \
    >/dev/null
# spc 需要 Composer 2；用官方安装器安装（发行版自带的是 1.x，过旧）
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
rm -f /tmp/composer-setup.php
bash /build-frankenphp.sh /src/frankenphp.tar.gz /out "'"$FP_VERSION"'"
chown -R "$HOST_UID:$HOST_GID" /out
'

echo "==> 断言 GLIBC 基线 ..."
bash "$HERE/assert-glibc-max.sh" "$OUT_DIR" "$GLIBC_MAX" "frankenphp"
echo "FRANKENPHP_GLIBC_BUILD_OK version=$FP_VERSION image=$IMAGE"
