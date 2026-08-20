#!/usr/bin/env bash
#
# 编译 Redis 官方源码（Linux x86_64）。
#
# 静态链接只通过 REDIS_LDFLAGS=-static 传给最终 redis-server/redis-cli 链接，
# 避免 LDFLAGS 传播到依赖（xxhash/tre 需要构建 .so，-static 会在 musl 下失败）。
# 首选 Alpine (musl) 静态编译（产物无 glibc 依赖）；Docker 不可用/失败时回退
# 宿主静态编译，再回退动态编译。每次尝试使用独立工作目录，互不污染。
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

DWORK=""
HWORK=""
cleanup() {
    # Docker 构建产物归 root，清理前先放开写权限；失败不阻断
    chmod -R u+w "$DWORK" "$HWORK" 2>/dev/null || true
    rm -rf "$DWORK" "$HWORK" 2>/dev/null || true
}
trap cleanup EXIT

src_name() { # src_name <tar> <workdir> -> 顶层目录名
    tar -tzf "$1" > "$2/list.txt"
    head -n1 "$2/list.txt" | cut -d/ -f1
}

copy_bins() { # copy_bins <src目录>：复制 redis-server / redis-cli
    cp "$1/src/redis-server" "$1/src/redis-cli" "$OUT_DIR/"
    chmod +x "$OUT_DIR/redis-server" "$OUT_DIR/redis-cli"
}

built=0

# 1) Alpine musl 静态（Docker 可用时）
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "==> 使用 Docker (Alpine musl) 静态编译 Redis $REDIS_VERSION ..."
    DWORK="$(mktemp -d)"
    tar -xzf "$SRC_TAR" -C "$DWORK"
    SRC_NAME="$(src_name "$SRC_TAR" "$DWORK")"
    cat > "$DWORK/build.sh" <<'SCRIPT'
#!/bin/sh
set -e
apk add --no-cache build-base linux-headers >/dev/null
cd "/work/$1"
make BUILD_TLS=no MALLOC=libc REDIS_LDFLAGS="-static" -j4 redis-server redis-cli
SCRIPT
    if docker run --rm -v "$DWORK":/work -w /work alpine:3.20 sh build.sh "$SRC_NAME"; then
        copy_bins "$DWORK/$SRC_NAME"
        built=1
    else
        echo "Docker 静态编译失败，回退宿主编译" >&2
    fi
    rm -rf "$DWORK" 2>/dev/null || true
    DWORK=""
fi

if [[ "$built" -eq 0 ]]; then
    HWORK="$(mktemp -d)"
    tar -xzf "$SRC_TAR" -C "$HWORK"
    SRC_NAME="$(src_name "$SRC_TAR" "$HWORK")"

    # 2) 宿主静态编译
    if make -C "$HWORK/$SRC_NAME" BUILD_TLS=no MALLOC=libc REDIS_LDFLAGS="-static" \
        -j"$(nproc)" redis-server redis-cli >/dev/null 2>&1; then
        echo "==> 宿主静态编译 Redis $REDIS_VERSION ..."
        copy_bins "$HWORK/$SRC_NAME"
        built=1
    else
        echo "宿主静态编译失败，回退动态编译" >&2
    fi

    # 3) 宿主动态编译（开发场景兜底）
    if [[ "$built" -eq 0 ]]; then
        echo "==> 宿主动态编译 Redis $REDIS_VERSION ..."
        if make -C "$HWORK/$SRC_NAME" BUILD_TLS=no MALLOC=libc \
            -j"$(nproc)" redis-server redis-cli; then
            copy_bins "$HWORK/$SRC_NAME"
            built=1
        fi
    fi
    rm -rf "$HWORK" 2>/dev/null || true
    HWORK=""
fi

if [[ "$built" -eq 0 ]]; then
    echo "Redis 编译失败" >&2
    exit 1
fi

if command -v file >/dev/null 2>&1; then
    file "$OUT_DIR/redis-server" | sed 's/^/  /'
fi
sha256sum "$OUT_DIR/redis-server" "$OUT_DIR/redis-cli"
echo "REDIS_BUILD_OK version=$REDIS_VERSION"
