#!/usr/bin/env bash
#
# 裁剪官方 MySQL 8.0 Community 通用二进制（Linux x86_64, glibc 2.17 基线）。
#
# 目标：安装体积控制在 30~45 MB，同时保持 CentOS 7（glibc >= 2.17）兼容。
#   - 输入官方 minimal tarball（已去除 debug 符号）：
#       mysql-8.0.46-linux-glibc2.17-x86_64-minimal.tar.xz
#   - 对 bin/ 与 lib/plugin/ 可执行文件执行 strip --strip-unneeded
#   - 删除 mysql-test/ docs/ man/ include/ *.a 等开发/测试文件
#   - 保留 lib/private（自带 OpenSSL，必须保留）、lib/plugin/、share/
#     （errmsg / charsets 运行时必需）与核心运维工具
#
# 用法: trim-mysql.sh <mysql-minimal.tar.xz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
MYSQL_VERSION="${3:-unknown}"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 MySQL 二进制包: $SRC_TAR" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 解压 MySQL $MYSQL_VERSION minimal 包 ..."
tar -xJf "$SRC_TAR" -C "$WORK"

# 扁平化顶层单目录（mysql-8.0.46-linux-glibc2.17-x86_64-minimal/）
SRC_NAME="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -print -quit | xargs -r basename)"
if [[ -n "$SRC_NAME" && -d "$WORK/$SRC_NAME" ]]; then
    cp -a "$WORK/$SRC_NAME/." "$OUT_DIR/"
else
    cp -a "$WORK/." "$OUT_DIR/"
fi

echo "==> strip 运行时二进制 ..."
if command -v strip >/dev/null 2>&1; then
    find "$OUT_DIR/bin" "$OUT_DIR/lib/plugin" -type f \
        -exec strip --strip-unneeded {} \; 2>/dev/null || true
fi

echo "==> 删除开发/测试文件（mysql-test docs man include *.a）..."
rm -rf \
    "$OUT_DIR/mysql-test" \
    "$OUT_DIR/docs" \
    "$OUT_DIR/man" \
    "$OUT_DIR/include" \
    "$OUT_DIR/support-files" \
    "$OUT_DIR/README" \
    "$OUT_DIR/README.txt" \
    "$OUT_DIR/INFO_BIN" \
    "$OUT_DIR/INFO_SRC" \
    "$OUT_DIR/COPYING" \
    "$OUT_DIR/LICENSE" \
    "$OUT_DIR/LICENSE.txt" 2>/dev/null || true
find "$OUT_DIR" \( -name '*.a' -o -name '*.la' -o -name '*.debug' -o -name '*.pdb' \) \
    -delete 2>/dev/null || true

echo "==> 删除大体积非必需组件（mecab 日文词典 129MB / 认证与复制插件）..."
# lib/mecab：Japanese fulltext parser 词典（FRAMPP 场景不需要，约 129MB）
rm -rf "$OUT_DIR/lib/mecab"
# 未在默认配置中加载的插件：kerberos / LDAP-SASL / OCI / FIDO 客户端认证、
# group replication、mecab 解析器、示例/测试插件
rm -f \
    "$OUT_DIR/lib/plugin/authentication_kerberos_client.so" \
    "$OUT_DIR/lib/plugin/authentication_ldap_sasl_client.so" \
    "$OUT_DIR/lib/plugin/authentication_oci_client.so" \
    "$OUT_DIR/lib/plugin/authentication_fido_client.so" \
    "$OUT_DIR/lib/plugin/group_replication.so" \
    "$OUT_DIR/lib/plugin/libpluginmecab.so" \
    "$OUT_DIR/lib/plugin/ha_example.so" \
    "$OUT_DIR/lib/plugin/ha_mock.so" \
    "$OUT_DIR/lib/plugin/adt_null.so" \
    "$OUT_DIR/lib/plugin/rewrite_example.so" 2>/dev/null || true

# 本地化错误消息只保留英文 + 简体中文（服务器默认英文，按需回退；省 ~8MB）
find "$OUT_DIR/share" -mindepth 1 -maxdepth 1 -type d \
    ! -name english ! -name chinese ! -name charsets ! -name aclocal \
    -exec rm -rf {} + 2>/dev/null || true
rm -rf "$OUT_DIR/share/aclocal"

echo "==> 删除非核心工具（保留运维必需命令）..."
keep_bin() {
    local name="$1"
    for k in mysqld mysql mysqladmin mysqldump mysqlcheck mysqlbinlog \
             mysql_ssl_rsa_setup mysql_upgrade my_print_defaults resolveip; do
        [[ "$name" == "$k" ]] && return 0
    done
    return 1
}
for f in "$OUT_DIR"/bin/*; do
    [[ -e "$f" || -L "$f" ]] || continue
    if ! keep_bin "$(basename "$f")"; then
        rm -f "$f"
    fi
done

# 删除不再需要的目录（pkgconfig 等）
rm -rf \
    "$OUT_DIR/lib/pkgconfig" \
    "$OUT_DIR/lib/cmake" 2>/dev/null || true

echo "==> 产物清单（保留目录）:"
du -sh "$OUT_DIR"
du -sh "$OUT_DIR"/bin "$OUT_DIR"/lib "$OUT_DIR"/share 2>/dev/null || true
du -sh "$OUT_DIR"/* 2>/dev/null | sort -h | tail -n 12 || true
ls -1 "$OUT_DIR/bin" 2>/dev/null || true
echo "MYSQL_TRIM_OK version=$MYSQL_VERSION"
