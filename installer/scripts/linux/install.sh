#!/usr/bin/env bash
#
# FRAMPP Linux 一键安装（XAMPP 风格：就地安装，目录可整体移动）
#
# 用法: ./install.sh
#
set -euo pipefail

FRAMPP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FRAMPP_HOME

echo "FRAMPP 一键安装（Linux x86_64）"
echo "安装目录: $FRAMPP_HOME"

# 校验组件完整性
for component in \
    "$FRAMPP_HOME/frankenphp/frankenphp" \
    "$FRAMPP_HOME/mariadb/bin/mariadbd" \
    "$FRAMPP_HOME/redis/redis-server"; do
    if [[ ! -x "$component" ]]; then
        echo "缺少组件: $component，安装包可能不完整" >&2
        exit 1
    fi
done

# 初始化（幂等：已存在 data/runtime.json 则跳过）
if [[ -f "$FRAMPP_HOME/data/runtime.json" ]]; then
    echo "已初始化（data/runtime.json 存在），跳过初始化。"
else
    bash "$FRAMPP_HOME/installer/scripts/linux/init.sh" --runtime-dir "$FRAMPP_HOME"
fi

# bin/frampp 包装器（缺失时补齐）
if [[ ! -x "$FRAMPP_HOME/bin/frampp" && -f "$FRAMPP_HOME/installer/scripts/linux/frampp-wrapper.sh" ]]; then
    cp "$FRAMPP_HOME/installer/scripts/linux/frampp-wrapper.sh" "$FRAMPP_HOME/bin/frampp"
    chmod +x "$FRAMPP_HOME/bin/frampp"
fi

# 启动全部服务
"$FRAMPP_HOME/bin/frampp" start all || true
"$FRAMPP_HOME/bin/frampp" status || true

cat <<EOF

安装完成！
  默认站点:   http://127.0.0.1:8080/
  控制面板:   http://127.0.0.1:8081/
  管理命令:   $FRAMPP_HOME/bin/frampp {status|start|stop|logs}
  数据库工具: $FRAMPP_HOME/mariadb/bin/mysql（root 密码见 data/secrets.json）
  卸载:       $FRAMPP_HOME/uninstall.sh

提示：目录可整体移动；移动后重新运行 $FRAMPP_HOME/install.sh 即可。
EOF
