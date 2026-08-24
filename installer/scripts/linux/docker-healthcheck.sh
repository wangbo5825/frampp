#!/usr/bin/env bash
#
# 容器健康检查：确认至少一个 FRAMPP 服务仍在运行。
#
set -euo pipefail

export FRAMPP_HOME="${FRAMPP_HOME:-/opt/frampp}"
status="$("$FRAMPP_HOME/bin/frampp" status --json 2>/dev/null || true)"
count="$(printf '%s' "$status" | grep -c '"running": true')"
test "$count" -eq 3
