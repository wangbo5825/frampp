#!/usr/bin/env bash
#
# 编译精简版 MariaDB（Linux x86_64）。
#
# 目标：安装体积控制在 30~50 MB。
#   - 源码编译（Release），CMake 禁用 PHP 场景几乎不用的存储引擎/插件：
#     RocksDB / Mroonga / Connect / Spider / Sphinx / S3 / OQGraph 等
#   - 对 bin/ 与 lib/plugin/ 全部可执行文件执行 strip --strip-unneeded
#   - 删除 mysql-test/ sql-bench/ man/ include/ lib/*.a 等开发/测试目录
#   - 保留 mysqld / mysql / mysqladmin / mysqldump / mysql_install_db 等核心工具
#
# 依赖（Debian/Ubuntu）：cmake, g++, bison, pkg-config, libssl-dev,
#   libpcre2-dev, zlib1g-dev, libncurses-dev, libcurl4-openssl-dev,
#   libxml2-dev
#
# 用法: build-mariadb.sh <mariadb-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
MDB_VERSION="${3:-unknown}"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 MariaDB 源码包: $SRC_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

for tool in cmake make g++ bison; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少构建工具: $tool（Debian/Ubuntu: sudo apt-get install cmake g++ bison ...）" >&2
        exit 1
    fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar -xzf "$SRC_TAR" -C "$WORK"
tar -tzf "$SRC_TAR" > "$WORK/list.txt"
SRC_NAME="$(head -n1 "$WORK/list.txt" | cut -d/ -f1)"
cd "$WORK/$SRC_NAME"

echo "==> CMake 配置 MariaDB $MDB_VERSION（Release，禁用重型插件）..."
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CONFIG=mysql_release \
    -DWITH_UNIT_TESTS=OFF \
    -DWITH_EMBEDDED_SERVER=OFF \
    -DPLUGIN_ROCKSDB=NO \
    -DPLUGIN_MROONGA=NO \
    -DPLUGIN_CONNECT=NO \
    -DPLUGIN_SPIDER=NO \
    -DPLUGIN_SPHINX=NO \
    -DPLUGIN_S3=NO \
    -DPLUGIN_OQGRAPH=NO \
    -DPLUGIN_TOKUDB=NO \
    -DPLUGIN_FEEDBACK=NO \
    -DPLUGIN_ARCHIVE=NO \
    -DPLUGIN_BLACKHOLE=NO \
    -DPLUGIN_EXAMPLE=NO \
    -DPLUGIN_DAEMON_EXAMPLE=NO \
    -DCMAKE_INSTALL_PREFIX="$OUT_DIR"

echo "==> 编译（$(nproc) 并行）..."
cmake --build build -j"$(nproc)"

echo "==> 安装到 $OUT_DIR ..."
cmake --install build

echo "==> strip 所有运行时二进制 ..."
if command -v strip >/dev/null 2>&1; then
    find "$OUT_DIR/bin" "$OUT_DIR/lib/plugin" -type f \
        -exec strip --strip-unneeded {} \; 2>/dev/null || true
fi

echo "==> 删除开发/测试文件（mysql-test sql-bench man include *.a）..."
rm -rf \
    "$OUT_DIR/mysql-test" \
    "$OUT_DIR/sql-bench" \
    "$OUT_DIR/man" \
    "$OUT_DIR/include"
find "$OUT_DIR" -name '*.a' -delete 2>/dev/null || true
find "$OUT_DIR" -name '*.la' -delete 2>/dev/null || true

# 删除仅开发/编译用工具（保留核心运维命令）
rm -f \
    "$OUT_DIR/bin/mysql_config" \
    "$OUT_DIR/bin/mariadb_config" \
    "$OUT_DIR/bin/mysqltest" \
    "$OUT_DIR/bin/mysql_client_test" 2>/dev/null || true

echo "==> 产物清单（保留目录）:"
du -sh "$OUT_DIR"
du -sh "$OUT_DIR"/bin "$OUT_DIR"/lib "$OUT_DIR"/share 2>/dev/null || true
echo "MARIADB_BUILD_OK version=$MDB_VERSION"
