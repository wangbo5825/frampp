#!/usr/bin/env bash
#
# 定制构建 FrankenPHP（Linux x86_64）。
#
# 基于官方 build-static.sh（static-php-cli / spc）：
#   - PHP 扩展：官方默认集去掉 intl / soap / gmp / bcmath / exif / imagick
#     （xdebug 不在官方默认集，天然不包含）
#   - Caddy 模块：去掉 Mercure / Vulcain，加入 Souin（HTTP 缓存）+ caddy-cbrotli
#   - SPC_LIBC=glibc：glibc mostly static（静态库除 glibc 外全部打入）
#   - COMPRESS=1：最终二进制用 UPX 压缩
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

# PHP 版本与精简扩展集（默认集去掉 intl/soap/gmp/bcmath/exif/imagick）
export PHP_VERSION="${FRAMPP_PHP_VERSION:-8.5.9}"
export PHP_EXTENSIONS="amqp,apcu,ast,brotli,bz2,calendar,ctype,curl,dba,dom,fileinfo,filter,ftp,gd,gettext,iconv,igbinary,ldap,lz4,mbregex,mbstring,memcached,mysqli,mysqlnd,opcache,openssl,password-argon2,parallel,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,posix,protobuf,readline,redis,session,shmop,simplexml,sockets,sodium,sqlite3,ssh2,sysvmsg,sysvsem,sysvshm,tidy,tokenizer,xlswriter,xml,xmlreader,xmlwriter,xsl,xz,zip,zlib,yaml,zstd"

# glibc mostly static + UPX 压缩
export SPC_LIBC="${FRAMPP_SPC_LIBC:-glibc}"
export COMPRESS=1

# 版本固定（解压目录无 .git，必须显式给出版本）
export FRANKENPHP_VERSION="${FP_VERSION#v}"

# Caddy 模块：去掉 Mercure/Vulcain，保留 cbrotli，加入 Souin（锁定兼容版本）
export SPC_CMD_VAR_FRANKENPHP_XCADDY_MODULES="--with github.com/dunglas/caddy-cbrotli --with github.com/darkweak/souin/plugins/caddy@65cb24114d76a7de3f4e8c7b8ef7df3efd028899 --with github.com/darkweak/souin@65cb24114d76a7de3f4e8c7b8ef7df3efd028899 --with github.com/darkweak/storages/otter/caddy"

echo "==> 构建 FrankenPHP $FRANKENPHP_VERSION（PHP $PHP_VERSION, libc=$SPC_LIBC, UPX=$COMPRESS）..."
echo "    扩展: ${PHP_EXTENSIONS//,/, }"
echo "    Caddy 模块: $SPC_CMD_VAR_FRANKENPHP_XCADDY_MODULES"
bash ./build-static.sh

echo "==> 复制产物到 $OUT_DIR ..."
cp "dist/frankenphp-linux-x86_64" "$OUT_DIR/frankenphp"
chmod +x "$OUT_DIR/frankenphp"

# sudo 重执行时产物归 root，交还属主给原用户，便于后续脚本读写
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "$OUT_DIR"
fi

echo "==> 验证:"
"$OUT_DIR/frankenphp" version
"$OUT_DIR/frankenphp" build-info || true
ls -lh "$OUT_DIR/frankenphp"
echo "FRANKENPHP_BUILD_OK version=$FP_VERSION"
