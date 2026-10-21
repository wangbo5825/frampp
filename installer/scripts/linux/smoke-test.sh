#!/usr/bin/env bash
#
# FRAMPP Linux 安装包冒烟测试（x86_64 / aarch64 共用）。
# 由 CI 在构建出 .run 之后调用；也可在本地解压后的目录中运行。
#
# 用法 / Usage:
#   smoke-test.sh <env> <glibc-baseline> [workspace-root]
#   例: smoke-test.sh linux-x86_64 2.17 "$GITHUB_WORKSPACE"
#       smoke-test.sh linux-aarch64 2.28 "$GITHUB_WORKSPACE"
#
set -euxo pipefail

ENV_NAME="${1:-linux-x86_64}"
GLIBC_BASELINE="${2:-2.17}"
WORKSPACE="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

cd dist/installer
PKG="$(ls frampp-*-"$ENV_NAME".run | head -n1)"
chmod +x "$PKG"
./"$PKG" --prefix "$PWD/frampp"
cd frampp

echo "=== env / platform ==="
uname -m
echo "=== init already ran inside .run; verify idempotent init ==="
./bin/frampp init
echo "=== Caddyfile ==="
cat etc/Caddyfile
echo "=== status ==="
./bin/frampp status --json || true
echo "=== version ==="
./bin/frampp version || true
echo "=== root master command (LAMPP-style symlink) ==="
ls -la frampp
if [ ! -L frampp ] || [ ! -e frampp ]; then
  echo "ROOT_FRAMPP_LINK_MISSING"; exit 1
fi
./frampp version || true
echo "=== runtime.json platform ==="
grep -o '"platform": *"[^"]*"' var/runtime.json || true
echo "=== apps layout ==="
test -d apps/default/htdocs
test -d apps/default/config
test -d apps/default/src
test -d apps/default/var
test -f apps/default/htdocs/index.php
test -f apps/default/htdocs/adminer.php
test -L htdocs
readlink htdocs
echo "=== extensions ==="
./modules/frankenphp/frankenphp php-cli -r "printf('apcu=%s redis=%s mysqli=%s pdo_sqlite=%s simplexml=%s openssl=%s%s', extension_loaded('apcu')?'yes':'NO', extension_loaded('redis')?'yes':'NO', extension_loaded('mysqli')?'yes':'NO', extension_loaded('pdo_sqlite')?'yes':'NO', extension_loaded('simplexml')?'yes':'NO', extension_loaded('openssl')?'yes':'NO', PHP_EOL);" || true
echo "=== pogo_scheduler module ==="
./modules/frankenphp/frankenphp list-modules | grep -q 'pogo_scheduler' || { echo "SCHEDULER_MODULE_MISSING"; exit 1; }
echo "SCHEDULER_MODULE_OK"
echo "=== caddy version (require >= 2.11.4) ==="
CADDY_FULL="$(./modules/frankenphp/frankenphp version 2>&1 || true)"
echo "$CADDY_FULL"
CADDY_VER="$(printf '%s\n' "$CADDY_FULL" | sed -n 's/.*Caddy v\([0-9][0-9.]*\).*/\1/p' | head -n1)"
ver_ge() { # ver_ge <a> <b> => a >= b
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}
if [[ -z "$CADDY_VER" ]]; then
  echo "CADDY_VERSION_UNKNOWN"; exit 1
fi
if ! ver_ge "$CADDY_VER" "2.11.4"; then
  echo "CADDY_VERSION_TOO_OLD ($CADDY_VER < 2.11.4)"; exit 1
fi
echo "CADDY_VERSION_OK $CADDY_VER"
echo "=== http 8080 (headers+body head) ==="
curl -sS -i --max-time 15 http://127.0.0.1:8080/ | head -n 30 || true
echo "=== http 8081 (headers+body head) ==="
curl -sS -i --max-time 15 http://127.0.0.1:8081/ | head -n 30 || true
echo "=== http 8081 direct /index.php (diagnostic) ==="
curl -sS -i --max-time 15 http://127.0.0.1:8081/index.php | head -n 20 || true
echo "=== http 8081 direct /action.php (diagnostic) ==="
curl -sS -i --max-time 15 http://127.0.0.1:8081/action.php | head -n 20 || true
echo "=== service err logs (diagnostic) ==="
tail -n 80 logs/frankenphp.err.log logs/mysql.err.log logs/redis.err.log 2>/dev/null || true
echo "=== panel must render (assert) ==="
PANEL_BODY="$(curl -sS --max-time 15 http://127.0.0.1:8081/ || true)"
if printf '%s' "$PANEL_BODY" | grep -q '<?php'; then
  echo "PANEL_SERVED_RAW_PHP"; exit 1
fi
if ! printf '%s' "$PANEL_BODY" | grep -q 'FRAMPP 控制面板'; then
  echo "PANEL_NOT_RENDERED"; exit 1
fi
echo "PANEL_OK"
echo "=== adapted config (routes per server) ==="
./modules/frankenphp/frankenphp adapt --config etc/Caddyfile --adapter caddyfile 2>/dev/null \
  | grep -o '"handler":"[a-z_]*"' | sort | uniq -c || true
echo "=== control-panel/web listing ==="
ls -la modules/control-panel/web || true
echo "=== slim checks (mysql-test must be gone) ==="
du -sh modules/mysql modules/python modules/frankenphp modules/redis || true
if [ -d modules/mysql/mysql-test ]; then
  echo "MYSQL_TEST_STILL_PRESENT"; exit 1
fi
echo "SLIM_OK"
echo "=== portability checks ==="
echo "--- FrankenPHP must be static (musl, no glibc dep) ---"
if file modules/frankenphp/frankenphp | grep -qi "statically linked"; then
  echo "FRANKENPHP_STATIC_OK"
else
  echo "FRANKENPHP_NOT_STATIC"; exit 1
fi
echo "--- MySQL glibc baseline must be <= $GLIBC_BASELINE ---"
bash "$WORKSPACE/installer/scripts/linux/assert-glibc-max.sh" modules/mysql "$GLIBC_BASELINE" mysql
echo "PORTABLE_OK"
echo "=== binary architecture check ==="
if command -v file >/dev/null 2>&1; then
  file modules/frankenphp/frankenphp modules/redis/redis-server modules/mysql/bin/mysqld | sed 's/^/  /'
fi
echo "=== service logs ==="
tail -n 60 logs/frankenphp.err.log 2>/dev/null || true
tail -n 40 logs/frankenphp.log 2>/dev/null || true
tail -n 60 logs/mysql.err.log 2>/dev/null || true
tail -n 40 logs/mysql.log 2>/dev/null || true
tail -n 40 logs/mysql-init.log logs/mysql-init-user.log 2>/dev/null || true
tail -n 20 logs/panel-access.log logs/frankenphp-access.log 2>/dev/null || true
echo "=== wait mysql port ==="
mysql_ready() { (exec 3<>/dev/tcp/127.0.0.1/3306) 2>/dev/null; }
for i in $(seq 1 30); do
  if mysql_ready; then echo "mysql port open after ${i}s"; break; fi
  sleep 1
done
mysql_ready || { echo "MYSQL_PORT_NOT_READY"; exit 1; }
ROOT_PW="$(sed -n 's/.*"mysql_root_password"[^"]*"\([^"]*\)".*/\1/p' var/secrets.json)"
REDIS_PW="$(sed -n 's/.*"redis_password"[^"]*"\([^"]*\)".*/\1/p' var/secrets.json)"
echo "--- MySQL via PHP PDO (mysqlnd, 与控制面板同一链路) ---"
ROOT_PW="$ROOT_PW" ./modules/frankenphp/frankenphp php-cli -r '
  $pdo = new PDO("mysql:host=127.0.0.1;port=3306;charset=utf8mb4", "root", getenv("ROOT_PW"), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 5]);
  echo "MYSQL_VERSION=", $pdo->query("SELECT VERSION()")->fetchColumn(), PHP_EOL;
'
echo "--- MySQL CLI (信息性；新 Debian/Ubuntu 可能缺 libtinfo.so.5) ---"
./modules/mysql/bin/mysql --no-defaults --connect-timeout=5 -h127.0.0.1 -P3306 -uroot -p"$ROOT_PW" -e "SELECT VERSION();" || true
./modules/redis/redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PW" --no-auth-warning ping
echo "=== restart all (v0.8.1 regression: port/socket release race) ==="
./bin/frampp restart all
for i in $(seq 1 30); do (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null && break; sleep 1; done
./modules/redis/redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PW" --no-auth-warning ping
echo "=== caddy-panel /panel api (after restart) ==="
curl -fsS http://127.0.0.1:8081/panel/api/status | head -c 300
echo
echo "=== pogo_scheduler smoke (HTTP mode, v0.8.2) ==="
cat > apps/default/htdocs/scheduler-smoke.php <<'PHP'
<?php
$log = dirname(__DIR__, 3) . '/var/scheduler-smoke.log';
file_put_contents($log, 'tick ' . date('c') . PHP_EOL, FILE_APPEND);
http_response_code(204);
PHP
cat > etc/scheduler.caddy <<'CADDY'
pogo_scheduler {
    mode http
    url http://127.0.0.1:8080/scheduler-smoke.php
    interval 2s
    timeout 5s
    overlap skip
}
CADDY
./bin/frampp restart frankenphp
SCHED_OK=0
for i in $(seq 1 30); do
  if [ -s var/scheduler-smoke.log ]; then SCHED_OK=1; break; fi
  sleep 1
done
if [ "$SCHED_OK" -ne 1 ]; then
  echo "SCHEDULER_NOT_FIRED"
  tail -n 40 logs/frankenphp.err.log logs/frankenphp.log 2>/dev/null || true
  exit 1
fi
echo "SCHEDULER_OK $(head -n1 var/scheduler-smoke.log)"
echo "=== stop ==="
./bin/frampp stop all || true
./bin/frampp status --json || true

echo "SMOKE_OK env=$ENV_NAME glibc<=$GLIBC_BASELINE"
