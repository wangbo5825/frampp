#!/usr/bin/env bash
#
# 定制构建 FrankenPHP（Linux: x86_64 / aarch64 —— 与构建主机架构一致）。
#
# 基于官方 build-static.sh（static-php-cli v3 / spc craft）：
#   - PHP 扩展：官方默认集去掉 intl / soap / gmp / bcmath / exif / imagick
#     （xdebug 不在官方默认集，天然不包含）
#   - Caddy 模块：去掉 Mercure / Vulcain，加入 Souin（HTTP 缓存）、caddy-cbrotli
#     与 caddy-access-filter（access/filter 可编程钩子）
#   - LIBC=musl：完全静态二进制（不依赖目标系统 libc）
#   - SPC_TARGET/CPU flags：固定最低 CPU 基线，禁止把构建机指令集带入发布包
#   - 默认不启用 UPX：static-php-cli v3 的 arm64 UPX 工具在部分构建环境不可执行
#   - Go 链接器 -w -s 去符号（spc 默认执行）
#
# 依赖：git, composer, curl, jq, 以及 build-static.sh 所需的编译工具链
#   （spc doctor --auto-fix 会尝试安装缺失工具）
#
# 用法: build-frankenphp.sh <frankenphp-源码-tar.gz> <输出目录> [版本]
#
set -euo pipefail

SRC_TAR="$1"
OUT_DIR="$2"
FP_VERSION="${3:-unknown}"

if [[ ! -f "$SRC_TAR" ]]; then
    echo "缺少 FrankenPHP 源码包: $SRC_TAR" >&2
    exit 1
fi

# spc doctor --auto-fix 需要 root 安装系统依赖；非 root 时自动通过 sudo 重执行
if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    echo "==> 需要 root 安装构建依赖，通过 sudo 重执行 ..."
    exec sudo -E env "PATH=$PATH" bash "$0" "$@"
fi

mkdir -p "$OUT_DIR"

for tool in git composer curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少构建工具: $tool" >&2
        exit 1
    fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tar -xzf "$SRC_TAR" -C "$WORK"
tar -tzf "$SRC_TAR" > "$WORK/list.txt"
SRC_NAME="$(head -n1 "$WORK/list.txt" | cut -d/ -f1)"
cd "$WORK/$SRC_NAME"

# PHP 8.5 的 FrankenPHP 1.13.2 不再提供 `frankenphp php-cli` 子命令；
# 同时构建独立 CLI SAPI，FRAMPP 才能保留标准 bin/php 命令。
if ! grep -q '^sapi:' craft.yml; then
    echo "缺少 FrankenPHP craft.yml sapi 配置" >&2
    exit 1
fi
sed -i 's/^sapi:.*/sapi: "frankenphp,cli"/' craft.yml

# PHP 版本与精简扩展集（默认集去掉 intl/soap/gmp/bcmath/exif/imagick）
# 8.5.12 修复 CVE-2026-109618 / CVE-2026-109619（PHP2Shell），不得降级。
export PHP_VERSION="${FRAMPP_PHP_VERSION:-8.5.12}"
export PHP_EXTENSIONS="amqp,apcu,ast,brotli,bz2,calendar,ctype,curl,dba,dom,fileinfo,filter,ftp,gd,gettext,iconv,igbinary,ldap,lz4,mbregex,mbstring,memcached,mysqli,mysqlnd,opcache,openssl,password-argon2,parallel,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,posix,protobuf,readline,redis,session,shmop,simplexml,sockets,sodium,sqlite3,ssh2,sysvmsg,sysvsem,sysvshm,tidy,tokenizer,xlswriter,xml,xmlreader,xmlwriter,xsl,xz,zip,zlib,yaml,zstd"

# static-php-cli v3 使用 LIBC 选择工具链；unset 旧 v2 变量，避免构建链混用。
export LIBC="${FRAMPP_SPC_LIBC:-musl}"
unset SPC_LIBC

# 发布包必须能在旧 CPU 上启动。尤其不能使用 SPC 默认的 native-native-*：
# 它会让 LLVM/Zig 按构建机 CPU 生成 AVX2/ADX 等指令。
SPC_BASE_CFLAGS="-fPIC -O3 -pipe -fno-plt -fno-semantic-interposition -fstack-clash-protection -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -ffunction-sections -fdata-sections -Wno-unused-command-line-argument"
BUILD_ARCH="$(uname -m)"
case "$BUILD_ARCH" in
    x86_64|amd64)
        export SPC_TARGET="x86_64-linux-musl"
        CPU_BASELINE="x86-64-v2"
        CPU_FLAGS="-march=x86-64-v2 -mtune=generic"
        export GOAMD64="v1"
        ;;
    aarch64|arm64)
        export SPC_TARGET="aarch64-linux-musl"
        CPU_BASELINE="generic"
        CPU_FLAGS="-mcpu=generic"
        ;;
    *)
        echo "不支持的构建架构 / unsupported build architecture: $BUILD_ARCH" >&2
        exit 1
        ;;
esac
export SPC_DEFAULT_CFLAGS="$SPC_BASE_CFLAGS $CPU_FLAGS"
export SPC_DEFAULT_CXXFLAGS="$SPC_DEFAULT_CFLAGS"
# 部分依赖直接读取 CFLAGS/CXXFLAGS；SPC_DEFAULT_* 负责库级完整参数。
export CFLAGS="$CPU_FLAGS"
export CXXFLAGS="$CPU_FLAGS"

if [[ "${FRAMPP_COMPRESS:-0}" == "1" ]]; then
    export COMPRESS=1
else
    unset COMPRESS
fi
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export SPC_GITHUB_TOKEN="$GITHUB_TOKEN"
fi

# 版本固定（解压目录无 .git，必须显式给出版本）
export FRANKENPHP_VERSION="${FP_VERSION#v}"

# Caddy 模块：去掉 Mercure/Vulcain，保留 cbrotli，加入 Souin（锁定兼容版本）
# 与 caddy-access-filter（access/filter 可编程钩子，v1.2.1：本地 IP/CIDR/国家码规则 + GeoIP）
# 注意：所有模块必须锁定版本，否则 xcaddy 取最新会导致 MVS 抬升 Caddy 版本，
# 不同架构/不同时间构建出的产物会出现版本漂移（0.8.1 曾出现 2.11.4 vs 2.11.7）。
# scheduler 的 go.mod 位于仓库 module/ 子目录。v0.2.0 支持多个独立 job，
# 仍保留 v0.1.0 顶层单任务语法兼容。
SCHEDULER_REF="${FRAMPP_SCHEDULER_REF:-2c8552504066cd276b704b7e6cc357405ef1b84b}"
export XCADDY_ARGS="--with github.com/dunglas/caddy-cbrotli@v1.0.1 --with github.com/darkweak/souin/plugins/caddy@65cb24114d76a7de3f4e8c7b8ef7df3efd028899 --with github.com/darkweak/souin@65cb24114d76a7de3f4e8c7b8ef7df3efd028899 --with github.com/darkweak/storages/otter/caddy@v0.0.20 --with github.com/wangbo5825/caddy-access-filter@v1.2.1 --with github.com/wangbo5825/scheduler/module@${SCHEDULER_REF}"

echo "==> 构建 FrankenPHP $FRANKENPHP_VERSION（PHP $PHP_VERSION, libc=$LIBC, target=$SPC_TARGET, cpu=$CPU_BASELINE, SPC=v3, UPX=${COMPRESS:-0}）..."
echo "    扩展: ${PHP_EXTENSIONS//,/, }"
echo "    CPU flags: $SPC_DEFAULT_CFLAGS"
echo "    scheduler ref: $SCHEDULER_REF"
echo "    Caddy 模块: $XCADDY_ARGS"
bash ./build-static.sh

echo "==> 复制产物到 $OUT_DIR ..."
# spc 按构建容器/主机架构命名产物（x86_64 / aarch64），这里按实际文件复制
FP_BIN="$(ls dist/frankenphp-linux-* 2>/dev/null | head -n1 || true)"
if [[ -z "$FP_BIN" ]]; then
    echo "未找到 spc 产物（dist/frankenphp-linux-*）" >&2
    exit 1
fi
cp "$FP_BIN" "$OUT_DIR/frankenphp"
chmod +x "$OUT_DIR/frankenphp"

PHP_BIN="dist/buildroot/bin/php"
if [[ ! -x "$PHP_BIN" ]]; then
    echo "未找到 PHP CLI 产物（$PHP_BIN）" >&2
    exit 1
fi
cp "$PHP_BIN" "$OUT_DIR/php"
chmod +x "$OUT_DIR/php"

{
    echo "frankenphp_version=$FRANKENPHP_VERSION"
    echo "php_version=$PHP_VERSION"
    echo "spc_target=$SPC_TARGET"
    echo "cpu_baseline=$CPU_BASELINE"
    echo "cpu_flags=$CPU_FLAGS"
    echo "scheduler_ref=$SCHEDULER_REF"
} > "$OUT_DIR/build-info.txt"

# sudo 重执行时产物归 root，交还属主给原用户，便于后续脚本读写
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "$OUT_DIR"
fi

echo "==> 验证:"
"$OUT_DIR/frankenphp" version
"$OUT_DIR/frankenphp" build-info || true
"$OUT_DIR/php" -v
ls -lh "$OUT_DIR/frankenphp" "$OUT_DIR/php"
echo "FRANKENPHP_BUILD_OK version=$FP_VERSION php=$PHP_VERSION target=$SPC_TARGET cpu=$CPU_BASELINE scheduler=$SCHEDULER_REF"
