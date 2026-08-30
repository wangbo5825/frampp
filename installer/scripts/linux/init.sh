#!/usr/bin/env bash
#
# FRAMPP Linux 运行时初始化（XAMPP 风格，自包含，无系统包管理依赖）
#
# 职责：
#   - 从缓存目录解压/复制组件（安装包场景下组件已就位，自动跳过）
#   - 生成随机密钥（var/secrets.json）
#   - 由模板生成 etc/php.ini / etc/redis.conf / etc/Caddyfile（无 BOM）
#   - 初始化 MariaDB 数据目录并创建只读账号 frampp_ro
#   - 写入 var/runtime.json（供控制面板发现运行时）
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
step "准备运行时布局 / preparing runtime layout: $RUNTIME_DIR"
mkdir -p \
    "$RUNTIME_DIR/modules/frankenphp" \
    "$RUNTIME_DIR/modules/mariadb" \
    "$RUNTIME_DIR/modules/redis" \
    "$RUNTIME_DIR/modules/python" \
    "$RUNTIME_DIR/modules/composer" \
    "$RUNTIME_DIR/modules/agent" \
    "$RUNTIME_DIR/modules/control-panel/web" \
    "$RUNTIME_DIR/modules/templates" \
    "$RUNTIME_DIR/bin" \
    "$RUNTIME_DIR/etc" \
    "$RUNTIME_DIR/etc/caddy.d" \
    "$RUNTIME_DIR/htdocs" \
    "$RUNTIME_DIR/logs" \
    "$RUNTIME_DIR/var/mariadb" \
    "$RUNTIME_DIR/var/redis"

# 2. 组件就位（安装包场景全部已存在；开发/构建场景从缓存补齐）
COMPONENT_DIR="$SCRIPT_DIR/../../config"
FRANKENPHP_VERSION="$(json_version "$VERSIONS_FILE" frankenphp)"
MARIADB_VERSION="$(json_version "$VERSIONS_FILE" mariadb)"
REDIS_VERSION="$(json_version "$VERSIONS_FILE" redis)"
COMPOSER_VERSION="$(json_version "$VERSIONS_FILE" composer)"
PYTHON_VERSION="$(json_version "$VERSIONS_FILE" python)"

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
    # FrankenPHP：源码 -> 定制编译（精简扩展 + Souin + UPX；已有二进制则跳过）
    if [[ ! -x "$RUNTIME_DIR/modules/frankenphp/frankenphp" ]]; then
        step "编译 FrankenPHP $FRANKENPHP_VERSION（定制 / custom build）..."
        bash "$SCRIPT_DIR/build-frankenphp.sh" \
            "$CACHE_DIR/frankenphp-v1.12.7.tar.gz" \
            "$RUNTIME_DIR/modules/frankenphp" \
            "$FRANKENPHP_VERSION"
    fi

    # MariaDB：源码 -> 精简编译（已有 mariadbd 则跳过）
    if [[ ! -x "$RUNTIME_DIR/modules/mariadb/bin/mariadbd" ]]; then
        step "编译 MariaDB $MARIADB_VERSION（精简版 / slim build）..."
        bash "$SCRIPT_DIR/build-mariadb.sh" \
            "$CACHE_DIR/mariadb-12.3.2.tar.gz" \
            "$RUNTIME_DIR/modules/mariadb" \
            "$MARIADB_VERSION"
    fi

    # Redis：官方源码 -> 静态编译（已有二进制则跳过）
    if [[ ! -x "$RUNTIME_DIR/modules/redis/redis-server" ]]; then
        step "编译 Redis $REDIS_VERSION（静态 / static）..."
        mkdir -p "$RUNTIME_DIR/modules/redis"
        bash "$SCRIPT_DIR/build-redis.sh" \
            "$CACHE_DIR/redis-8.10.1.tar.gz" \
            "$RUNTIME_DIR/modules/redis" \
            "$REDIS_VERSION"
    fi

    # Python：独立精简运行时（install_only_stripped + 二次精简）
    if [[ ! -x "$RUNTIME_DIR/modules/python/bin/python3" ]]; then
        step "准备 Python $PYTHON_VERSION（精简独立运行时 / standalone runtime）..."
        bash "$SCRIPT_DIR/build-python.sh" \
            "$CACHE_DIR/cpython-3.13.15-linux-x86_64-install_only_stripped.tar.gz" \
            "$RUNTIME_DIR/modules/python" \
            "$PYTHON_VERSION"
    fi
fi

# 3. Composer / Adminer（单文件组件）
if [[ ! -f "$RUNTIME_DIR/modules/composer/composer.phar" && -f "$CACHE_DIR/composer.phar" ]]; then
    cp "$CACHE_DIR/composer.phar" "$RUNTIME_DIR/modules/composer/composer.phar"
fi
if [[ ! -f "$RUNTIME_DIR/htdocs/adminer.php" && -f "$CACHE_DIR/adminer-6.0.1.php" ]]; then
    cp "$CACHE_DIR/adminer-6.0.1.php" "$RUNTIME_DIR/htdocs/adminer.php"
fi

# 4. 项目模板 / 默认站点首页
if [[ ! -d "$RUNTIME_DIR/modules/templates/project-minimal" && -d "$COMPONENT_DIR/../templates/project-minimal" ]]; then
    cp -a "$COMPONENT_DIR/../templates/project-minimal" "$RUNTIME_DIR/modules/templates/"
fi
if [[ ! -f "$RUNTIME_DIR/htdocs/index.php" && -f "$COMPONENT_DIR/../templates/htdocs/index.php" ]]; then
    cp "$COMPONENT_DIR/../templates/htdocs/index.php" "$RUNTIME_DIR/htdocs/index.php"
fi

# 5. 随机密钥（仅首次生成）
SECRETS_FILE="$RUNTIME_DIR/var/secrets.json"
if [[ ! -f "$SECRETS_FILE" ]]; then
    step "生成随机密钥 / generating secrets ..."
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

json_value() { # json_value <file> <key>
    awk -v k="$2" '
        $0 ~ "\"" k "\"[[:space:]]*:" {
            v=$0; sub(/^.*:[[:space:]]*"/, "", v); sub(/".*$/, "", v); print v; exit
        }
    ' "$1"
}

# 6. 配置文件（模板 -> 运行时）
step "生成配置 / generating configs ..."
TPL_DIR="$COMPONENT_DIR/../templates"

# 传输模式：默认 tcp；已存在的运行时保留其模式（sock 为 unix socket，仅 Linux）
MODE="tcp"
if [[ -f "$RUNTIME_DIR/var/runtime.json" ]]; then
    MODE="$(json_value "$RUNTIME_DIR/var/runtime.json" mode)"
    [[ -z "$MODE" ]] && MODE="tcp"
fi
RUN_DIR="$RUNTIME_DIR/var/run"
ADMIN_ADDR="127.0.0.1:2019"
UNIX_SOCKET_CONF=""
MYSQL_SOCKET=""
if [[ "$MODE" == "sock" ]]; then
    mkdir -p "$RUN_DIR"
    ADMIN_ADDR="unix//$RUN_DIR/admin.sock"
    UNIX_SOCKET_CONF="unixsocket $RUN_DIR/redis.sock
unixsocketperm 700"
    MYSQL_SOCKET="$RUN_DIR/mysql.sock"
fi

fill_template "$TPL_DIR/php.ini.linux.template" "$RUNTIME_DIR/etc/php.ini" \
    MYSQL_SOCKET "$MYSQL_SOCKET"

fill_template "$TPL_DIR/redis.conf.template" "$RUNTIME_DIR/etc/redis.conf" \
    REDIS_PASSWORD "$REDIS_PW" \
    DATA_DIR "$RUNTIME_DIR/var/redis" \
    LOG_FILE "$RUNTIME_DIR/logs/redis.log" \
    UNIX_SOCKET_CONF "$UNIX_SOCKET_CONF"

# IP 访问控制（Linux 定制构建内置 caddy-access-filter v1.2.0）
ACCESS_CONFIG="$RUNTIME_DIR/etc/access.json"
ACCESS_RULES="$RUNTIME_DIR/etc/access-filter.rules"
if [[ ! -f "$ACCESS_CONFIG" ]]; then
    cat > "$ACCESS_CONFIG" <<EOF
{
    "enabled": true,
    "supported": true,
    "default_action": "allow",
    "geoip_db": "",
    "geoip_format": ""
}
EOF
fi
if [[ ! -f "$ACCESS_RULES" ]]; then
    printf '# FRAMPP IP 访问规则 / IP access rules\n# 格式 / format: <IP|CIDR|code:XX> <allow|block>\n' > "$ACCESS_RULES"
fi
CADDY_D="$RUNTIME_DIR/etc/caddy.d"
if [[ ! -f "$CADDY_D/00-default.caddy" ]]; then
    printf '# 在此目录放置额外的站点配置（*.caddy）\n# Place additional site configs (*.caddy) in this directory.\n' \
        > "$CADDY_D/00-default.caddy"
fi

ACCESS_ENABLED="$(json_value "$ACCESS_CONFIG" enabled)"
ACCESS_DEFAULT="$(json_value "$ACCESS_CONFIG" default_action)"
[[ -z "$ACCESS_DEFAULT" ]] && ACCESS_DEFAULT="allow"
GEOIP_DB="$(json_value "$ACCESS_CONFIG" geoip_db)"
GEOIP_FORMAT="$(json_value "$ACCESS_CONFIG" geoip_format)"

ACCESS_CADDY="$RUNTIME_DIR/etc/access-filter.caddy"
if [[ "$ACCESS_ENABLED" == "true" ]]; then
    {
        echo "access {"
        echo "    name frampp_access"
        echo "    rules file $ACCESS_RULES"
        echo "    default_action $ACCESS_DEFAULT"
        if [[ -n "$GEOIP_DB" ]]; then
            echo "    geoip {"
            echo "        database $GEOIP_DB"
            echo "        format ${GEOIP_FORMAT:-mmdb}"
            echo "    }"
        fi
        echo "}"
    } > "$ACCESS_CADDY"
    ACCESS_IMPORT="import $ACCESS_CADDY"
else
    printf '# access-filter disabled\n' > "$ACCESS_CADDY"
    ACCESS_IMPORT="# access-filter disabled"
fi

fill_template "$TPL_DIR/Caddyfile.template" "$RUNTIME_DIR/etc/Caddyfile" \
    HTDOCS "$RUNTIME_DIR/htdocs" \
    PANEL_ROOT "$RUNTIME_DIR/modules/control-panel/web" \
    LOGS_DIR "$RUNTIME_DIR/logs" \
    ACCESS_IMPORT "$ACCESS_IMPORT" \
    CADDY_D "$CADDY_D" \
    ADMIN_ADDR "$ADMIN_ADDR"

# 运行时命令包装与符号链接
RUNTIME_BIN_SRC="$RUNTIME_DIR/installer/runtime/bin"
if [[ ! -d "$RUNTIME_BIN_SRC" && -d "$ROOT/installer/runtime/bin" ]]; then
    RUNTIME_BIN_SRC="$ROOT/installer/runtime/bin"
fi
if [[ -d "$RUNTIME_BIN_SRC" ]]; then
    cp -f "$RUNTIME_BIN_SRC"/frampp "$RUNTIME_BIN_SRC"/php \
          "$RUNTIME_BIN_SRC"/composer "$RUNTIME_BIN_SRC"/python \
          "$RUNTIME_BIN_SRC"/pip "$RUNTIME_BIN_SRC"/env \
          "$RUNTIME_BIN_SRC"/uninstall "$RUNTIME_BIN_SRC"/framppd \
          "$RUNTIME_BIN_SRC"/install-systemd "$RUNTIME_BIN_SRC"/frampp-mcp \
          "$RUNTIME_DIR/bin/"
fi
ln -sfn "$RUNTIME_DIR/modules/frankenphp/frankenphp" "$RUNTIME_DIR/bin/frankenphp" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mariadb/bin/mysql" "$RUNTIME_DIR/bin/mysql" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mariadb/bin/mariadb" "$RUNTIME_DIR/bin/mariadb" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mariadb/bin/mysqladmin" "$RUNTIME_DIR/bin/mysqladmin" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mariadb/bin/mysqldump" "$RUNTIME_DIR/bin/mysqldump" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/redis/redis-cli" "$RUNTIME_DIR/bin/redis-cli" 2>/dev/null || true

# systemd 单元（安装后可用 bin/install-systemd 安装）
SYSTEMD_TPL="$RUNTIME_DIR/installer/runtime/frampp.service.template"
if [[ ! -f "$SYSTEMD_TPL" && -f "$ROOT/installer/runtime/frampp.service.template" ]]; then
    SYSTEMD_TPL="$ROOT/installer/runtime/frampp.service.template"
fi
if [[ -f "$SYSTEMD_TPL" ]]; then
    sed "s|__FRAMPP_HOME__|$RUNTIME_DIR|g" \
        "$SYSTEMD_TPL" \
        > "$RUNTIME_DIR/etc/frampp.service"
fi

# 可执行位（解压 umask 差异兜底）
chmod +x \
    "$RUNTIME_DIR/modules/frankenphp/frankenphp" \
    "$RUNTIME_DIR/modules/redis/redis-server" \
    "$RUNTIME_DIR/modules/redis/redis-cli" \
    "$RUNTIME_DIR/bin"/* \
    "$RUNTIME_DIR/installer/scripts/linux/init.sh" \
    "$RUNTIME_DIR/installer/scripts/linux/docker-entrypoint.sh" \
    "$RUNTIME_DIR/installer/scripts/linux/docker-healthcheck.sh" 2>/dev/null || true
if [[ -d "$RUNTIME_DIR/modules/mariadb/bin" ]]; then
    chmod +x "$RUNTIME_DIR/modules/mariadb/bin"/* 2>/dev/null || true
fi
if [[ -d "$RUNTIME_DIR/modules/mariadb/scripts" ]]; then
    chmod +x "$RUNTIME_DIR/modules/mariadb/scripts"/* 2>/dev/null || true
fi
if [[ -d "$RUNTIME_DIR/modules/python/bin" ]]; then
    chmod +x "$RUNTIME_DIR/modules/python/bin"/* 2>/dev/null || true
fi

# 7. MariaDB 数据目录初始化
DB_INITIALIZED=0
MYSQL_BIN="$RUNTIME_DIR/modules/mariadb/bin"
INSTALL_DB="$RUNTIME_DIR/modules/mariadb/scripts/mariadb-install-db"
if [[ ! -x "$INSTALL_DB" ]]; then
    INSTALL_DB="$MYSQL_BIN/mariadb-install-db"
fi
if [[ "$SKIP_DB_INIT" -eq 0 && -x "$INSTALL_DB" ]]; then
    DATADIR="$RUNTIME_DIR/var/mariadb"
    if [[ ! -d "$DATADIR/mysql" ]]; then
        step "初始化 MariaDB 数据目录 / initializing MariaDB datadir ..."
        "$INSTALL_DB" --no-defaults \
            --datadir="$DATADIR" \
            --auth-root-authentication-method=normal \
            > "$RUNTIME_DIR/logs/mariadb-install-db.log" 2>&1 || \
            { cat "$RUNTIME_DIR/logs/mariadb-install-db.log" 2>/dev/null || true; \
              warn "mariadb-install-db 失败 / failed，见 / see logs/mariadb-install-db.log"; }
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

        step "临时启动 MariaDB 创建账号 / bootstrapping MariaDB accounts ..."
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
                    warn "MariaDB 密码验证失败 / password verification failed，见 / see $BOOTSTRAP_LOG"
                fi
                "$MYSQL_BIN/mysqladmin" --no-defaults --connect-timeout=5 \
                    -h 127.0.0.1 -P "$MYSQL_PORT" -u root -p"$ROOT_PW" shutdown \
                    >> "$BOOTSTRAP_LOG" 2>&1 || true
            else
                warn "MariaDB 账号初始化失败 / account init failed，见 / see $BOOTSTRAP_LOG"
            fi
        else
            warn "MariaDB 未能监听端口 $MYSQL_PORT，跳过只读账号创建 / port not ready, skipped read-only account; 日志见 / log: $ERR_LOG"
        fi
        # 兜底关闭
        if kill -0 "$DB_PID" 2>/dev/null; then
            sleep 1
            kill -9 "$DB_PID" 2>/dev/null || true
        fi
    fi
fi

# 8. 运行时清单
step "写入运行时清单 / writing runtime manifest ..."
cat > "$RUNTIME_DIR/var/runtime.json" <<EOF
{
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "root": "$RUNTIME_DIR",
    "platform": "linux-x86_64",
    "ports": { "http": $HTTP_PORT, "panel": $PANEL_PORT, "mysql": $MYSQL_PORT, "redis": $REDIS_PORT },
    "components": {
        "frankenphp": "$FRANKENPHP_VERSION",
        "mariadb": "$MARIADB_VERSION",
        "redis": "$REDIS_VERSION",
        "composer": "$COMPOSER_VERSION",
        "python": "$PYTHON_VERSION"
    },
    "db_initialized": $DB_INITIALIZED
}
EOF

step "完成 / done. 运行时就绪 / runtime ready: $RUNTIME_DIR"
echo "DB_INITIALIZED=$DB_INITIALIZED"
