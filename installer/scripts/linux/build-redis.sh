#!/usr/bin/env bash
#
# 编译 Redis 官方源码（Linux x86_64）。
# 首选 Alpine (musl) 静态编译：产物无 glibc 依赖，可在多数发行版直接运行；
# 若本机无可用 Docker，回退到宿主静态编译，再回退动态编译。
#
# 用法: build-redis.sh <redis-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
REDIS_VERSION="${3:-unknown}"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 Redis 源码包: $SRC_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar -xzf "$SRC_TAR" -C "$WORK"
# 先落盘再取首行，避免 tar | head 在 pipefail 下触发 SIGPIPE
tar -tzf "$SRC_TAR" > "$WORK/list.txt"
SRC_NAME="$(head -n1 "$WORK/list.txt" | cut -d/ -f1)"
SRC_DIR="$WORK/$SRC_NAME"

BUILD_ARGS=(BUILD_TLS=no MALLOC=libc)
STATIC_ARGS=("${BUILD_ARGS[@]}" "LDFLAGS=-static")

built=0

# 1) Alpine musl 静态（Docker 可用时）
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "==> 使用 Docker (Alpine musl) 静态编译 Redis $REDIS_VERSION ..."
    cat > "$WORK/build.sh" <<'SCRIPT'
#!/bin/sh
set -e
apk add --no-cache build-base linux-headers >/dev/null
cd "/work/$1"
make BUILD_TLS=no MALLOC=libc LDFLAGS="-static" -j4 redis-server redis-cli
SCRIPT
    if docker run --rm -v "$WORK":/work -w /work alpine:3.20 sh build.sh "$SRC_NAME"; then
        built=1
    else
        echo "Docker 静态编译失败，回退宿主编译" >&2
    fi
fi

# 2) 宿主静态编译
if [[ "$built" -eq 0 ]] && make -C "$SRC_DIR" "${STATIC_ARGS[@]}" -j"$(nproc)" redis-server redis-cli >/dev/null 2>&1; then
    echo "==> 宿主静态编译 Redis $REDIS_VERSION ..."
    built=1
fi

# 3) 宿主动态编译（开发场景兜底）
if [[ "$built" -eq 0 ]]; then
    echo "==> 宿主动态编译 Redis $REDIS_VERSION ..."
    make -C "$SRC_DIR" "${BUILD_ARGS[@]}" -j"$(nproc)" redis-server redis-cli
    built=1
fi

cp "$SRC_DIR/src/redis-server" "$SRC_DIR/src/redis-cli" "$OUT_DIR/"
chmod +x "$OUT_DIR/redis-server" "$OUT_DIR/redis-cli"

if command -v file >/dev/null 2>&1; then
    file "$OUT_DIR/redis-server" | sed 's/^/  /'
fi
sha256sum "$OUT_DIR/redis-server" "$OUT_DIR/redis-cli"
echo "REDIS_BUILD_OK version=$REDIS_VERSION"
