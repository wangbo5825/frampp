#!/usr/bin/env bash
#
# FRAMPP Linux 运行时初始化（XAMPP 风格，自包含，无系统包管理依赖）
#
# 职责：
#   - 从缓存目录解压/复制组件（安装包场景下组件已就位，自动跳过）
#   - 生成随机密钥（data/secrets.json）
#   - 由模板生成 php.ini / redis.conf / Caddyfile（无 BOM）
#   - 初始化 MariaDB 数据目录并创建只读账号 frampp_ro
#   - 写入 data/runtime.json（供控制面板发现运行时）
#
# 用法：
#   init.sh --runtime-dir <dir> [--cache-dir <dir>] [--skip-db-init]
#
set -euo pipefail

ROOT=""
CACHE_DIR=""
RUNTIME_DIR=""
SKIP_DB_INIT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --runtime-dir) RUNTIME_DIR="$2"; shift 2 ;;
        --skip-db-init) SKIP_DB_INIT=1; shift ;;
        -h|--help)
            echo "用法: init.sh --runtime-dir <dir> [--cache-dir <dir>] [--skip-db-init]"
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$ROOT" ]]; then ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"; fi
if [[ -z "$CACHE_DIR" ]]; then CACHE_DIR="$ROOT/dist/binaries"; fi
if [[ -z "$RUNTIME_DIR" ]]; then RUNTIME_DIR="$ROOT/dist/runtime-linux"; fi

# 版本清单：安装包内自带；开发场景回退到仓库
VERSIONS_FILE="${FRAMPP_VERSIONS_FILE:-}"
if [[ -z "$VERSIONS_FILE" ]]; then
    if [[ -f "$RUNTIME_DIR/installer/config/versions-linux-x86_64.json" ]]; then
        VERSIONS_FILE="$RUNTIME_DIR/installer/config/versions-linux-x86_64.json"
    else
        VERSIONS_FILE="$ROOT/installer/config/versions-linux-x86_64.json"
    fi
fi

# 端口（与控制面板 / Windows 安装一致）
HTTP_PORT=8080
PANEL_PORT=8081
MYSQL_PORT=3306
REDIS_PORT=6379

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*" >&2; }

gen_hex() { # gen_hex <bytes>
    local n="$1"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$n"
    else
        head -c "$n" /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

json_version() { # json_version <file> <component> -> version
    awk -v c="$2" '
        $0 ~ "\"" c "\"[[:space:]]*:[[:space:]]*\\{" { in_c=1; next }
        in_c && /"version"/ {
            v=$0; sub(/^.*"version"[[:space:]]*:[[:space:]]*"/, "", v);
            sub(/".*$/, "", v); print v; exit
        }
    ' "$1"
}

fill_template() { # fill_template <tpl> <out> <KEY> <VAL> ...
    local tpl="$1" out="$2"; shift 2
    local content
    content="$(cat "$tpl")"
    while [[ $# -gt 0 ]]; do
        local k="$1" v="$2"; shift 2
        v="${v//&/\\&}"
        content="$(printf '%s' "$content" | sed "s|{{$k}}|$v|g")"
    done
    printf '%s\n' "$content" > "$out"
}

mkdir -p "$RUNTIME_DIR"
RUNTIME_DIR="$(cd "$RUNTIME_DIR" && pwd)"

# 1. 布局
step "准备运行时布局: $RUNTIME_DIR"
mkdir -p \
    "$RUNTIME_DIR/frankenphp" \
    "$RUNTIME_DIR/mariadb" \
    "$RUNTIME_DIR/redis" \
    "$RUNTIME_DIR/bin" \
    "$RUNTIME_DIR/htdocs" \
    "$RUNTIME_DIR/logs" \
    "$RUNTIME_DIR/data/mariadb" \
    "$RUNTIME_DIR/data/redis"

# 2. 组件就位（安装包场景全部已存在；开发/构建场景从缓存补齐）
COMPONENT_DIR="$SCRIPT_DIR/../../config"
FRANKENPHP_VERSION="$(json_version "$VERSIONS_FILE" frankenphp)"
MARIADB_VERSION="$(json_version "$VERSIONS_FILE" mariadb)"
REDIS_VERSION="$(json_version "$VERSIONS_FILE" redis)"
COMPOSER_VERSION="$(json_version "$VERSIONS_FILE" composer)"

extract_nested() { # 提升顶层单目录，保持扁平布局
    local dir="$1"
    local entries
    entries=("$dir"/*)
    if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
        local nested="${entries[0]}"
        cp -a "$nested/." "$dir/"
        rm -rf "$nested"
    fi
}

if [[ -d "$CACHE_DIR" ]]; then
    # FrankenPHP：单文件静态二进制
    if [[ ! -x "$RUNTIME_DIR/frankenphp/frankenphp" ]]; then
        step "安装 FrankenPHP $FRANKENPHP_VERSION ..."
        cp "$CACHE_DIR/frankenphp-linux-x86_64" "$RUNTIME_DIR/frankenphp/frankenphp"
        chmod +x "$RUNTIME_DIR/frankenphp/frankenphp"
    fi

    # MariaDB：bintar tarball
    if [[ ! -x "$RUNTIME_DIR/mariadb/bin/mariadbd" ]]; then
        step "解压 MariaDB $MARIADB_VERSION ..."
        tar -xzf "$CACHE_DIR/mariadb-12.3.2-linux-systemd-x86_64.tar.gz" -C "$RUNTIME_DIR/mariadb"
        extract_nested "$RUNTIME_DIR/mariadb"
    fi

    # Redis：官方源码 -> 静态编译（已有二进制则跳过）
    if [[ ! -x "$RUNTIME_DIR/redis/redis-server" ]]; then
        step "编译 Redis $REDIS_VERSION（静态）..."
        mkdir -p "$RUNTIME_DIR/redis"
        bash "$SCRIPT_DIR/build-redis.sh" \
            "$CACHE_DIR/redis-8.10.1.tar.gz" \
            "$RUNTIME_DIR/redis" \
            "$REDIS_VERSION"
    fi
fi

# 3. Composer / Adminer（单文件组件）
if [[ ! -f "$RUNTIME_DIR/bin/composer.phar" && -f "$CACHE_DIR/composer.phar" ]]; then
    cp "$CACHE_DIR/composer.phar" "$RUNTIME_DIR/bin/composer.phar"
fi
if [[ ! -f "$RUNTIME_DIR/htdocs/adminer.php" && -f "$CACHE_DIR/adminer-6.0.1.php" ]]; then
    cp "$CACHE_DIR/adminer-6.0.1.php" "$RUNTIME_DIR/htdocs/adminer.php"
fi

# 4. 默认站点首页
if [[ ! -f "$RUNTIME_DIR/htdocs/index.php" && -f "$COMPONENT_DIR/../templates/htdocs/index.php" ]]; then
    cp "$COMPONENT_DIR/../templates/htdocs/index.php" "$RUNTIME_DIR/htdocs/index.php"
fi

# 5. 随机密钥（仅首次生成）
SECRETS_FILE="$RUNTIME_DIR/data/secrets.json"
if [[ ! -f "$SECRETS_FILE" ]]; then
    step "生成随机密钥 ..."
    cat > "$SECRETS_FILE" <<EOF
{
    "mariadb_root_password": "$(gen_hex 24)",
    "mariadb_readonly_password": "$(gen_hex 24)",
    "redis_password": "$(gen_hex 24)",
    "panel_token": "$(gen_hex 16)"
}
EOF
fi

# 读取密钥（供配置模板 / 数据库初始化使用）
secret() { # secret <key>
    awk -v k="$1" '
        $0 ~ "\"" k "\"[[:space:]]*:" {
            v=$0; sub(/^.*:[[:space:]]*"/, "", v); sub(/".*$/, "", v); print v; exit
        }
    ' "$SECRETS_FILE"
}
ROOT_PW="$(secret mariadb_root_password)"
RO_PW="$(secret mariadb_readonly_password)"
REDIS_PW="$(secret redis_password)"

# 6. 配置文件（模板 -> 运行时）
step "生成配置 ..."
TPL_DIR="$COMPONENT_DIR/../templates"
cp "$TPL_DIR/php.ini.linux.template" "$RUNTIME_DIR/frankenphp/php.ini"

fill_template "$TPL_DIR/redis.conf.template" "$RUNTIME_DIR/redis/redis.conf" \
    REDIS_PASSWORD "$REDIS_PW" \
    DATA_DIR "$RUNTIME_DIR/data/redis" \
    LOG_FILE "$RUNTIME_DIR/logs/redis.log"

fill_template "$TPL_DIR/Caddyfile.template" "$RUNTIME_DIR/Caddyfile" \
    HTDOCS "$RUNTIME_DIR/htdocs" \
    PANEL_ROOT "$RUNTIME_DIR/control-panel/web" \
    LOGS_DIR "$RUNTIME_DIR/logs"

# 可执行位（解压 umask 差异兜底）
chmod +x \
    "$RUNTIME_DIR/frankenphp/frankenphp" \
    "$RUNTIME_DIR/redis/redis-server" \
    "$RUNTIME_DIR/redis/redis-cli" \
    "$RUNTIME_DIR/bin/frampp" \
    "$RUNTIME_DIR/installer/scripts/linux/init.sh" \
    "$RUNTIME_DIR/install.sh" \
    "$RUNTIME_DIR/uninstall.sh" 2>/dev/null || true
if [[ -d "$RUNTIME_DIR/mariadb/bin" ]]; then
    chmod +x "$RUNTIME_DIR/mariadb/bin"/* 2>/dev/null || true
fi
if [[ -d "$RUNTIME_DIR/mariadb/scripts" ]]; then
    chmod +x "$RUNTIME_DIR/mariadb/scripts"/* 2>/dev/null || true
fi

# 7. MariaDB 数据目录初始化
DB_INITIALIZED=0
MYSQL_BIN="$RUNTIME_DIR/mariadb/bin"
INSTALL_DB="$RUNTIME_DIR/mariadb/scripts/mariadb-install-db"
if [[ ! -x "$INSTALL_DB" ]]; then
    INSTALL_DB="$MYSQL_BIN/mariadb-install-db"
fi
if [[ "$SKIP_DB_INIT" -eq 0 && -x "$INSTALL_DB" ]]; then
    DATADIR="$RUNTIME_DIR/data/mariadb"
    if [[ ! -d "$DATADIR/mysql" ]]; then
        step "初始化 MariaDB 数据目录 ..."
        "$INSTALL_DB" --no-defaults \
            --datadir="$DATADIR" \
            --auth-root-authentication-method=normal \
            > "$RUNTIME_DIR/logs/mariadb-install-db.log" 2>&1 || \
            warn "mariadb-install-db 失败，见 logs/mariadb-install-db.log"
    fi

    if [[ -d "$DATADIR/mysql" ]]; then
        ERR_LOG="$RUNTIME_DIR/logs/mariadb.err.log"
        BOOTSTRAP_LOG="$RUNTIME_DIR/logs/mariadb-init-user.log"
        SQL="CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$ROOT_PW';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$ROOT_PW';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PW';
CREATE USER IF NOT EXISTS 'frampp_ro'@'127.0.0.1' IDENTIFIED BY '$RO_PW';
GRANT SELECT, SHOW VIEW ON *.* TO 'frampp_ro'@'127.0.0.1';
FLUSH PRIVILEGES;"

        step "临时启动 MariaDB 创建账号 ..."
        "$MYSQL_BIN/mariadbd" --no-defaults \
            --datadir="$DATADIR" \
            --port="$MYSQL_PORT" \
            --bind-address=127.0.0.1 \
            --user="$(id -un)" \
            --log-error="$ERR_LOG" &
        DB_PID=$!

        PORT_READY=0
        for _ in $(seq 1 60); do
            if timeout 1 bash -c "</dev/tcp/127.0.0.1/$MYSQL_PORT" 2>/dev/null; then
                PORT_READY=1
                break
            fi
            sleep 0.5
        done

        if [[ "$PORT_READY" -eq 1 ]]; then
            if "$MYSQL_BIN/mysql" --no-defaults --connect-timeout=5 \
                -h 127.0.0.1 -P "$MYSQL_PORT" -u root -e "$SQL" >> "$BOOTSTRAP_LOG" 2>&1; then
                # 用新密码验证后优雅关闭
                if "$MYSQL_BIN/mysql" --no-defaults --connect-timeout=5 \
                    -h 127.0.0.1 -P "$MYSQL_PORT" -u root -p"$ROOT_PW" \
                    -e "SELECT 'init-ok' AS result;" >> "$BOOTSTRAP_LOG" 2>&1; then
                    DB_INITIALIZED=1
                else
                    warn "MariaDB 密码验证失败，见 $BOOTSTRAP_LOG"
                fi
                "$MYSQL_BIN/mysqladmin" --no-defaults --connect-timeout=5 \
                    -h 127.0.0.1 -P "$MYSQL_PORT" -u root -p"$ROOT_PW" shutdown \
                    >> "$BOOTSTRAP_LOG" 2>&1 || true
            else
                warn "MariaDB 账号初始化失败，见 $BOOTSTRAP_LOG"
            fi
        else
            warn "MariaDB 未能监听端口 $MYSQL_PORT，跳过只读账号创建；日志见 $ERR_LOG"
        fi
        # 兜底关闭
        if kill -0 "$DB_PID" 2>/dev/null; then
            sleep 1
            kill -9 "$DB_PID" 2>/dev/null || true
        fi
    fi
fi

# 8. 运行时清单
step "写入运行时清单 ..."
cat > "$RUNTIME_DIR/data/runtime.json" <<EOF
{
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "root": "$RUNTIME_DIR",
    "platform": "linux-x86_64",
    "ports": { "http": $HTTP_PORT, "panel": $PANEL_PORT, "mysql": $MYSQL_PORT, "redis": $REDIS_PORT },
    "components": {
        "frankenphp": "$FRANKENPHP_VERSION",
        "mariadb": "$MARIADB_VERSION",
        "redis": "$REDIS_VERSION",
        "composer": "$COMPOSER_VERSION"
    },
    "db_initialized": $DB_INITIALIZED
}
EOF

step "完成 / done. 运行时就绪 / runtime ready: $RUNTIME_DIR"
echo "DB_INITIALIZED=$DB_INITIALIZED"
