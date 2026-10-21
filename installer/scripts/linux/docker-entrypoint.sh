#!/usr/bin/env bash
#
# FRAMPP Docker 入口：首启动初始化运行时，然后启动三件套并保持容器存活。
#
# 与 Linux 一键安装包共享同一运行时布局与 init.sh。数据、日志与站点目录
# 建议挂载为卷，避免容器删除后丢失（apps/、var/、logs/；旧 htdocs/ 兼容）。
#
set -euo pipefail

FRAMPP_HOME="${FRAMPP_HOME:-/opt/frampp}"
export FRAMPP_HOME
export PATH="$FRAMPP_HOME/bin:$FRAMPP_HOME/modules/python/bin:$FRAMPP_HOME/modules/mysql/bin:$FRAMPP_HOME/modules/redis:$PATH"

log() { printf '\033[36m[FRAMPP]\033[0m %s\n' "$*"; }

# etc/ 不在卷中：容器重建后需要重新生成配置；apps/var/logs 由卷持久化。
if [[ ! -f "$FRAMPP_HOME/var/runtime.json" || ! -f "$FRAMPP_HOME/etc/Caddyfile" ]]; then
    log "Initializing runtime (secrets, MySQL datadir, configs) / 初始化运行时..."
    if [[ -f "$FRAMPP_HOME/bin/init.sh" ]]; then
        bash "$FRAMPP_HOME/bin/init.sh" --runtime-dir "$FRAMPP_HOME"
    else
        bash "$FRAMPP_HOME/installer/scripts/linux/init.sh" --runtime-dir "$FRAMPP_HOME"
    fi
fi

stop_all() {
    log "Stopping services / 正在停止服务 ..."
    "$FRAMPP_HOME/bin/frampp" stop all || true
    exit 0
}
trap stop_all INT TERM

log "Starting all services / 启动全部服务 ..."
"$FRAMPP_HOME/bin/frampp" start all || true
"$FRAMPP_HOME/bin/frampp" status || true

log "FRAMPP is ready / FRAMPP 已就绪："
log "  Default site / 默认站点: http://127.0.0.1:8080/"
log "  Control panel / 控制面板: http://127.0.0.1:8081/"

# 保持前台进程，确保容器不会退出；同时将 SIGTERM/SIGINT 转给清理逻辑。
sleep infinity &
wait $!
