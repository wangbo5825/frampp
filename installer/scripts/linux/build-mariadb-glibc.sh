#!/usr/bin/env bash
#
# 在固定旧 glibc 基线容器内编译精简版 MariaDB。
#
# glibc 是向下兼容的：在新 glibc 上编译的二进制无法在旧 glibc 上运行，
# 反之则可以。因此为兼容更多旧发行版，必须在足够旧的 glibc 环境里编译。
# 默认使用 ubuntu:20.04（glibc 2.31），覆盖 Ubuntu 20.04+ / Debian 11+ / RHEL 9+。
#
# 环境变量:
#   FRAMPP_GLIBC_IMAGE  构建镜像（默认 ubuntu:20.04）
#   FRAMPP_GLIBC_MAX    允许的最高 GLIBC 符号版本（默认 2.31）
#
# 用法: build-mariadb-glibc.sh <mariadb-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
MDB_VERSION="${3:-unknown}"
IMAGE="${FRAMPP_GLIBC_IMAGE:-ubuntu:20.04}"
GLIBC_MAX="${FRAMPP_GLIBC_MAX:-2.31}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 MariaDB 源码包: $SRC_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
SRC_TAR_ABS="$(abs "$SRC_TAR")"
OUT_DIR_ABS="$(abs "$OUT_DIR")"

# Docker 不可用时回退宿主裸编译（兼容无 Docker 的开发场景，但 glibc 基线可能过高）
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "==> Docker 不可用，回退宿主裸编译（注意：glibc 基线可能过高）" >&2
    exec bash "$HERE/build-mariadb.sh" "$SRC_TAR" "$OUT_DIR" "$MDB_VERSION"
fi

echo "==> 使用 Docker ($IMAGE) 固定 glibc 基线编译 MariaDB $MDB_VERSION ..."
docker run --rm \
    -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
    -v "$SRC_TAR_ABS:/src/mariadb.tar.gz:ro" \
    -v "$OUT_DIR_ABS:/out" \
    -v "$HERE/build-mariadb.sh:/build-mariadb.sh:ro" \
    "$IMAGE" bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y --no-install-recommends \
    build-essential cmake bison pkg-config \
    libssl-dev libpcre2-dev zlib1g-dev libncurses-dev libcurl4-openssl-dev \
    libxml2-dev libaio-dev liburing-dev libgnutls28-dev liblz4-dev libedit-dev \
    libsnappy-dev libpam0g-dev libkrb5-dev libsystemd-dev libcrack2-dev libcap-dev \
    >/dev/null
bash /build-mariadb.sh /src/mariadb.tar.gz /out "'"$MDB_VERSION"'"
chown -R "$HOST_UID:$HOST_GID" /out
'

echo "==> 断言 GLIBC 基线 ..."
bash "$HERE/assert-glibc-max.sh" "$OUT_DIR" "$GLIBC_MAX" "mariadb"
echo "MARIADB_GLIBC_BUILD_OK version=$MDB_VERSION image=$IMAGE"
