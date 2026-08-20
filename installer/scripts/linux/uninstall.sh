#!/usr/bin/env bash
#
# FRAMPP Linux 卸载：停止服务，可选删除数据。
#
set -euo pipefail

FRAMPP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "$FRAMPP_HOME/bin/frampp" ]]; then
    echo "正在停止服务 / stopping services ..."
    "$FRAMPP_HOME/bin/frampp" stop all || true
fi
echo "服务已停止 / services stopped."

read -r -p "是否删除数据与日志（data/、logs/，不可恢复）？/ Delete data & logs (irreversible)? [y/N] " ans
case "$ans" in
    y|Y|yes|YES)
        rm -rf "$FRAMPP_HOME/data" "$FRAMPP_HOME/logs"
        echo "已删除 / deleted data/ and logs/."
        ;;
    *)
        echo "已保留 / kept data/ and logs/."
        ;;
esac

echo "如需完全移除，请删除目录 / to fully remove, delete: $FRAMPP_HOME"
