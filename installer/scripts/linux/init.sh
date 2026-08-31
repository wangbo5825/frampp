#!/usr/bin/env bash
#
# FRAMPP Linux 运行时初始化（XAMPP 风格，自包含，无系统包管理依赖）
#
# 职责：
#   - 从缓存目录解压/复制组件（安装包场景下组件已就位，自动跳过）
#   - 生成随机密钥（var/secrets.json）
#   - 由模板生成 etc/php.ini / etc/redis.conf / etc/Caddyfile（无 BOM）
#   - 初始化 MySQL 数据目录并创建只读账号 frampp_ro
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
    if [[ -f "$RUNTIME_DIR/share/versions-linux-x86_64.json" ]]; then
        VERSIONS_FILE="$RUNTIME_DIR/share/versions-linux-x86_64.json"
    elif [[ -f "$RUNTIME_DIR/installer/config/versions-linux-x86_64.json" ]]; then
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
    "$RUNTIME_DIR/modules/mysql" \
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
    "$RUNTIME_DIR/var/mysql" \
    "$RUNTIME_DIR/var/redis"

# 2. 组件就位（安装包场景全部已存在；开发/构建场景从缓存补齐）
COMPONENT_DIR="$SCRIPT_DIR/../../config"
FRANKENPHP_VERSION="$(json_version "$VERSIONS_FILE" frankenphp)"
MYSQL_VERSION="$(json_version "$VERSIONS_FILE" mysql)"
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

    # MySQL 8.0：官方 glibc 2.17 minimal -> 裁剪（已有 mysqld 则跳过）
    if [[ ! -x "$RUNTIME_DIR/modules/mysql/bin/mysqld" ]]; then
        step "裁剪 MySQL $MYSQL_VERSION（官方 glibc 2.17 / slim trim）..."
        bash "$SCRIPT_DIR/trim-mysql.sh" \
            "$CACHE_DIR/mysql-8.0.46-linux-glibc2.17-x86_64-minimal.tar.xz" \
            "$RUNTIME_DIR/modules/mysql" \
            "$MYSQL_VERSION"
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
TPL_SRC=""
if [[ -d "$RUNTIME_DIR/share/templates/project-minimal" ]]; then
    TPL_SRC="$RUNTIME_DIR/share/templates"
elif [[ -d "$COMPONENT_DIR/../templates/project-minimal" ]]; then
    TPL_SRC="$COMPONENT_DIR/../templates"
elif [[ -d "$RUNTIME_DIR/installer/templates/project-minimal" ]]; then
    TPL_SRC="$RUNTIME_DIR/installer/templates"
fi
if [[ -n "$TPL_SRC" ]]; then
    if [[ ! -d "$RUNTIME_DIR/modules/templates/project-minimal" ]]; then
        cp -a "$TPL_SRC/project-minimal" "$RUNTIME_DIR/modules/templates/"
    fi
    if [[ ! -f "$RUNTIME_DIR/htdocs/index.php" ]]; then
        cp "$TPL_SRC/htdocs/index.php" "$RUNTIME_DIR/htdocs/index.php"
    fi
fi

# 5. 随机密钥（仅首次生成）
SECRETS_FILE="$RUNTIME_DIR/var/secrets.json"
if [[ ! -f "$SECRETS_FILE" ]]; then
    step "生成随机密钥 / generating secrets ..."
    cat > "$SECRETS_FILE" <<EOF
{
    "mysql_root_password": "$(gen_hex 24)",
    "mysql_readonly_password": "$(gen_hex 24)",
    "redis_password": "$(gen_hex 24)",
    "panel_token": "$(gen_hex 16)"
}
EOF
elif ! grep -q '"mysql_root_password"' "$SECRETS_FILE"; then
    # 升级兼容：0.6.0 及更早只有 mariadb_* 键，补充 mysql_* 密钥
    step "升级运行时：补充 MySQL 密钥 / upgraded runtime: adding MySQL secrets ..."
    FRAMPP_SECRETS_FILE="$SECRETS_FILE" \
    FRAMPP_ROOT_PW="$(gen_hex 24)" \
    FRAMPP_RO_PW="$(gen_hex 24)" \
        "$RUNTIME_DIR/modules/frankenphp/frankenphp" php-cli -r '
            $f = getenv("FRAMPP_SECRETS_FILE");
            $d = json_decode((string) file_get_contents($f), true);
            $d["mysql_root_password"] = getenv("FRAMPP_ROOT_PW");
            $d["mysql_readonly_password"] = getenv("FRAMPP_RO_PW");
            file_put_contents($f, json_encode($d, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL);
        ' || warn "MySQL 密钥补充失败 / failed to add MySQL secrets"
fi

# 读取密钥（供配置模板 / 数据库初始化使用）
secret() { # secret <key>
    awk -v k="$1" '
        $0 ~ "\"" k "\"[[:space:]]*:" {
            v=$0; sub(/^.*:[[:space:]]*"/, "", v); sub(/".*$/, "", v); print v; exit
        }
    ' "$SECRETS_FILE"
}
ROOT_PW="$(secret mysql_root_password)"
RO_PW="$(secret mysql_readonly_password)"
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
TPL_DIR="$RUNTIME_DIR/share/templates"
if [[ ! -f "$TPL_DIR/php.ini.linux.template" && -d "$COMPONENT_DIR/../templates" ]]; then
    TPL_DIR="$COMPONENT_DIR/../templates"
fi
if [[ ! -f "$TPL_DIR/php.ini.linux.template" && -d "$RUNTIME_DIR/installer/templates" ]]; then
    TPL_DIR="$RUNTIME_DIR/installer/templates"
fi

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
REDIS_LISTEN_PORT="$REDIS_PORT"
if [[ "$MODE" == "sock" ]]; then
    mkdir -p "$RUN_DIR"
    ADMIN_ADDR="unix//$RUN_DIR/admin.sock"
    UNIX_SOCKET_CONF="unixsocket $RUN_DIR/redis.sock
unixsocketperm 700"
    MYSQL_SOCKET="$RUN_DIR/mysql.sock"
    REDIS_LISTEN_PORT="0"
fi

fill_template "$TPL_DIR/php.ini.linux.template" "$RUNTIME_DIR/etc/php.ini" \
    MYSQL_SOCKET "$MYSQL_SOCKET"

fill_template "$TPL_DIR/redis.conf.template" "$RUNTIME_DIR/etc/redis.conf" \
    REDIS_PASSWORD "$REDIS_PW" \
    DATA_DIR "$RUNTIME_DIR/var/redis" \
    LOG_FILE "$RUNTIME_DIR/logs/redis.log" \
    UNIX_SOCKET_CONF "$UNIX_SOCKET_CONF" \
    REDIS_PORT "$REDIS_LISTEN_PORT"

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
# 安装包内 bin/ 已直接携带包装器；开发/旧布局下补齐缺失的命令
if [[ -d "$RUNTIME_BIN_SRC" ]]; then
    for _f in frampp php composer python pip env uninstall framppd install-systemd frampp-mcp; do
        if [[ ! -f "$RUNTIME_DIR/bin/$_f" && -f "$RUNTIME_BIN_SRC/$_f" ]]; then
            cp -f "$RUNTIME_BIN_SRC/$_f" "$RUNTIME_DIR/bin/"
        fi
    done
fi
ln -sfn "$RUNTIME_DIR/modules/frankenphp/frankenphp" "$RUNTIME_DIR/bin/frankenphp" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mysql/bin/mysql" "$RUNTIME_DIR/bin/mysql" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mysql/bin/mysqladmin" "$RUNTIME_DIR/bin/mysqladmin" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mysql/bin/mysqldump" "$RUNTIME_DIR/bin/mysqldump" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/mysql/bin/mysqlcheck" "$RUNTIME_DIR/bin/mysqlcheck" 2>/dev/null || true
ln -sfn "$RUNTIME_DIR/modules/redis/redis-cli" "$RUNTIME_DIR/bin/redis-cli" 2>/dev/null || true
# LAMPP 风格根目录总控命令：frampp -> bin/frampp（打包阶段已创建；解压/手工拷贝时兜底）
ln -sfn "$RUNTIME_DIR/bin/frampp" "$RUNTIME_DIR/frampp" 2>/dev/null || true

# systemd 单元（安装后可用 bin/install-systemd 安装）
SYSTEMD_TPL="$RUNTIME_DIR/share/templates/frampp.service.template"
if [[ ! -f "$SYSTEMD_TPL" && -f "$RUNTIME_DIR/installer/runtime/frampp.service.template" ]]; then
    SYSTEMD_TPL="$RUNTIME_DIR/installer/runtime/frampp.service.template"
fi
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
    "$RUNTIME_DIR/bin/init.sh" \
    "$RUNTIME_DIR/bin/docker-entrypoint.sh" \
    "$RUNTIME_DIR/bin/docker-healthcheck.sh" 2>/dev/null || true
if [[ -d "$RUNTIME_DIR/modules/mysql/bin" ]]; then
    chmod +x "$RUNTIME_DIR/modules/mysql/bin"/* 2>/dev/null || true
fi
if [[ -d "$RUNTIME_DIR/modules/mysql/lib/plugin" ]]; then
    chmod +x "$RUNTIME_DIR/modules/mysql/lib/plugin"/* 2>/dev/null || true
fi
if [[ -d "$RUNTIME_DIR/modules/python/bin" ]]; then
    chmod +x "$RUNTIME_DIR/modules/python/bin"/* 2>/dev/null || true
fi

# 7. MySQL 数据目录初始化
DB_INITIALIZED=0
MYSQL_BIN="$RUNTIME_DIR/modules/mysql/bin"
MYSQLD="$MYSQL_BIN/mysqld"
FRANKENPHP_BIN="$RUNTIME_DIR/modules/frankenphp/frankenphp"

# 通过 PHP PDO（mysqlnd，走 unix socket）执行引导 SQL。
# 避免依赖 mysql CLI 在新发行版缺 libtinfo.so.5 的问题；服务端本身不依赖 ncurses。
mysql_php() { # mysql_php <socket> <password> <sql-file 或 "-">
    local sock="$1" pw="$2" sql="$3"
    FRAMPP_BOOT_SOCKET="$sock" FRAMPP_BOOT_PW="$pw" FRAMPP_BOOT_SQL="$sql" \
        PHPRC="$RUNTIME_DIR/etc/php.ini" \
        "$FRANKENPHP_BIN" php-cli -r '
            $sock = getenv("FRAMPP_BOOT_SOCKET");
            $pw = getenv("FRAMPP_BOOT_PW");
            $sql = getenv("FRAMPP_BOOT_SQL");
            $pdo = new PDO(
                "mysql:unix_socket=$sock;charset=utf8mb4",
                "root",
                $pw,
                [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]
            );
            if ($sql !== "" && $sql !== "-") {
                $pdo->exec((string) file_get_contents($sql));
            } else {
                $pdo->query("SELECT 1");
            }
        '
}

if [[ "$SKIP_DB_INIT" -eq 0 && -x "$MYSQLD" ]]; then
    DATADIR="$RUNTIME_DIR/var/mysql"
    # 0.6.0 及以前的 MariaDB 数据目录与 MySQL 8.0 不兼容：
    # 检测到旧数据（有 mysql/ 但无 MySQL 8.0 的 mysql.ibd）时，整体移到备份目录保留，
    # 然后重建 MySQL 数据目录（用户可手动导入备份数据）。
    if [[ -d "$DATADIR" && ! -f "$DATADIR/mysql.ibd" && -n "$(ls -A "$DATADIR" 2>/dev/null || true)" ]]; then
        BACKUP_DIR="$RUNTIME_DIR/var/mysql-mariadb-backup-$(date +%Y%m%d%H%M%S)"
        step "检测到不兼容的旧数据库数据目录，已备份 / incompatible legacy datadir backed up: $BACKUP_DIR"
        mv "$DATADIR" "$BACKUP_DIR"
        mkdir -p "$DATADIR"
    fi
    if [[ ! -d "$DATADIR/mysql" || ! -f "$DATADIR/mysql.ibd" ]]; then
        step "初始化 MySQL 数据目录 / initializing MySQL datadir ..."
        mkdir -p "$DATADIR"
        "$MYSQLD" --no-defaults --initialize-insecure \
            --basedir="$RUNTIME_DIR/modules/mysql" \
            --datadir="$DATADIR" \
            --user="$(id -un)" \
            --log-error="$RUNTIME_DIR/logs/mysql-init.log" 2>&1 || \
            { cat "$RUNTIME_DIR/logs/mysql-init.log" 2>/dev/null || true; \
              warn "mysqld --initialize-insecure 失败 / failed，见 / see logs/mysql-init.log"; }
    fi

    if [[ -d "$DATADIR/mysql" ]]; then
        # 幂等：已在之前初始化过（runtime.json 标记）则跳过账号引导
        DB_ALREADY_INIT=0
        if [[ -f "$RUNTIME_DIR/var/runtime.json" ]]; then
            DB_ALREADY_INIT="$(json_value "$RUNTIME_DIR/var/runtime.json" db_initialized)"
        fi
        if [[ "$DB_ALREADY_INIT" -eq 1 ]]; then
            DB_INITIALIZED=1
        else
        ERR_LOG="$RUNTIME_DIR/logs/mysql.err.log"
        BOOTSTRAP_LOG="$RUNTIME_DIR/logs/mysql-init-user.log"
        SQL_FILE="$RUNTIME_DIR/var/mysql-init.sql"
        RUN_DIR="$RUNTIME_DIR/var/run"
        BOOT_SOCKET="$RUN_DIR/mysql-init.sock"
        mkdir -p "$RUN_DIR"
        rm -f "$BOOT_SOCKET"
        cat > "$SQL_FILE" <<EOF
# 账号显式使用 mysql_native_password：caching_sha2 在非 TLS TCP 下需要 RSA 公钥，
# 会兼容性收窄 PHP（mysqlnd）/ Adminer / CLI 等客户端；FRAMPP 仅绑定 127.0.0.1。
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$ROOT_PW';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$ROOT_PW';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'frampp_ro'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$RO_PW';
GRANT SELECT, SHOW VIEW ON *.* TO 'frampp_ro'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

        step "临时启动 MySQL 创建账号 / bootstrapping MySQL accounts ..."
        "$MYSQLD" --no-defaults \
            --basedir="$RUNTIME_DIR/modules/mysql" \
            --datadir="$DATADIR" \
            --skip-networking \
            --socket="$BOOT_SOCKET" \
            --user="$(id -un)" \
            --log-error="$ERR_LOG" &
        DB_PID=$!

        PORT_READY=0
        for _ in $(seq 1 60); do
            if [[ -S "$BOOT_SOCKET" ]]; then
                PORT_READY=1
                break
            fi
            sleep 0.5
        done

        if [[ "$PORT_READY" -eq 1 ]]; then
            if mysql_php "$BOOT_SOCKET" "" "$SQL_FILE" >> "$BOOTSTRAP_LOG" 2>&1; then
                # 用新密码验证后优雅关闭
                if mysql_php "$BOOT_SOCKET" "$ROOT_PW" "-" >> "$BOOTSTRAP_LOG" 2>&1; then
                    DB_INITIALIZED=1
                else
                    warn "MySQL 密码验证失败 / password verification failed，见 / see $BOOTSTRAP_LOG"
                fi
            else
                warn "MySQL 账号初始化失败 / account init failed，见 / see $BOOTSTRAP_LOG"
            fi
        else
            warn "MySQL 未能就绪（socket: $BOOT_SOCKET），跳过只读账号创建 / not ready, skipped read-only account; 日志见 / log: $ERR_LOG"
        fi
        # 优雅关闭（SIGTERM），兜底强杀
        if kill -0 "$DB_PID" 2>/dev/null; then
            kill -TERM "$DB_PID" 2>/dev/null || true
            for _ in $(seq 1 20); do
                kill -0 "$DB_PID" 2>/dev/null || break
                sleep 0.5
            done
            kill -9 "$DB_PID" 2>/dev/null || true
        fi
        rm -f "$SQL_FILE" "$BOOT_SOCKET"
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
        "mysql": "$MYSQL_VERSION",
        "redis": "$REDIS_VERSION",
        "composer": "$COMPOSER_VERSION",
        "python": "$PYTHON_VERSION"
    },
    "db_initialized": $DB_INITIALIZED
}
EOF

step "完成 / done. 运行时就绪 / runtime ready: $RUNTIME_DIR"
echo "DB_INITIALIZED=$DB_INITIALIZED"
